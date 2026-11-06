namespace SpiderBuddy.Core;

/// <summary>
/// Stage 18.1 — talking. The spider's own words are an optional layer over the ordinary thought
/// packs: right-clicking it (or its bubble) opens the chat, and a passing thought may be written
/// for the moment. With the switch off, nothing here changes the desktop behaviour.
/// </summary>
public sealed partial class Spider
{
    /// <summary>The platform-independent words hook (spec 18.1). The host supplies a backend.</summary>
    public static ISpiderWords? Words;

    public bool Listening { get; private set; }
    public bool HoldStillToTalk => Listening;
    public bool CanTalk => Design.Intelligence && Words is { Status: VoiceStatus.Ready };

    public readonly List<string> RecentMuses = new();
    int _museRequest;

    /// <summary>Stops decisions and walking while the chat is open, without moving its feet.</summary>
    public void BeginListening()
    {
        if (Listening) return;
        Listening = true;
        if (Mode == Mode.Attached && !InHammock)
        {
            Speed = 0;
            TargetSpeed = 0;
            Play(Activity.Idle, 1);
        }
    }

    public void EndListening()
    {
        if (!Listening) return;
        Listening = false;
        Activity = Activity.Idle;
        ActivityTime = 0;
        ActivityDur = 1;
        DecisionIn = Math.Max(DecisionIn, 1.2);
    }

    /// <summary>Say something in the bubble when a reply comes back; the feeling moves the body.</summary>
    public void Speak(string text, Feeling feeling)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        CurrentThought = ThoughtKind.Text;
        CurrentThoughtText = text;
        _thoughtFrom = Time;
        _thoughtUntil = Time + 7.0;
        ApplyFeeling(feeling);
    }

    /// <summary>A passing thought from the model arrives (or does not, in which case the old voice plays).</summary>
    void ShowMuse(string? line)
    {
        if (string.IsNullOrWhiteSpace(line) || CurrentThought != ThoughtKind.Dots) return;
        CurrentThought = ThoughtKind.Text;
        CurrentThoughtText = line;
        _thoughtFrom = Time;
        _thoughtUntil = Time + 3.2;
    }

    /// <summary>
    /// Try the talking-spider path from Muse(). Returns false when it should fall back to the
    /// ordinary picture/phrase behaviour: the switch is off, no backend is ready, or it is busy.
    /// </summary>
    bool TryTalkingMuse()
    {
        if (!CanTalk || Words is not { } words) return false;
        // 30% of the time a verse is shown exactly as written; 20% one of the person's own lines.
        if (Design.Packs.Any(SpiderPhrases.IsVersePack) && Rng.Chance(0.30)
            && SpiderPhrases.RandomLine(Design, Rng, versesOnly: true) is { } verse)
        {
            CurrentThought = ThoughtKind.Text;
            CurrentThoughtText = verse;
            _thoughtFrom = Time;
            _thoughtUntil = Time + 3.2;
            return true;
        }
        if (Rng.Chance(0.20) && SpiderPhrases.RandomLine(Design, Rng) is { } written)
        {
            CurrentThought = ThoughtKind.Text;
            CurrentThoughtText = written;
            _thoughtFrom = Time;
            _thoughtUntil = Time + 3.2;
            return true;
        }

        string spark = Spark();
        var avoid = RecentMuses.TakeLast(5).ToList();
        RecentMuses.Add(spark);
        if (RecentMuses.Count > 8) RecentMuses.RemoveRange(0, RecentMuses.Count - 8);
        CurrentThought = ThoughtKind.Dots;
        CurrentThoughtText = null;
        _thoughtFrom = Time;
        _thoughtUntil = Time + 20.0;
        int serial = ++_museRequest;
        _ = AskMusingAsync(words, spark, avoid, serial);
        return true;
    }

    async Task AskMusingAsync(ISpiderWords words, string spark, IReadOnlyList<string> avoid, int serial)
    {
        string? line = null;
        try { line = await words.MuseAsync(Design.Clone(), spark, avoid); }
        catch { }
        if (serial != _museRequest || !Design.Intelligence) return;
        ShowMuse(line);
    }

    /// <summary>The single concrete thing a passing thought is about (spec 18.1, weighted).</summary>
    public string Spark()
    {
        var choices = new List<(double weight, string spark)>
        {
            (2, "the person"),
            (1, "something fun you did"),
            (1, "a game"),
            (1, "the window you are on"),
            (1, "your silk hammock"),
            (1, "being sleepy")
        };
        if (LoosePrey > 0) choices.Add((5, "a little bug wandering about"));
        if (Fed < 0.25) choices.Add((3, "being hungry"));
        else if (Fed > 0.85) choices.Add((2, "having a full tummy"));
        if (MusicPlaying) choices.Add((4, "the music"));
        if (Raining) choices.Add((4, WeatherCode is >= 95 ? "the storm" : "the rain"));
        if (Night) choices.Add((3, "it being night"));
        if (Design.Packs.Contains("verses")) choices.Add((2, "a kind verse"));
        if (Design.Packs.Contains("encouragement")) choices.Add((2, "a reminder for the person"));
        if (Design.Packs.Contains("spider")) choices.Add((2, "being a spider"));
        var weights = choices.Select(c => c.weight).ToArray();
        return choices[Math.Min(choices.Count - 1, Rng.WeightedIndex(weights))].spark;
    }

    /// <summary>The background handed to a reply, never brought up unless the person asks.</summary>
    public string Situation()
    {
        var parts = new List<string>();
        if (MusicPlaying) parts.Add("music is playing");
        if (Night) parts.Add("it is night");
        if (Raining) parts.Add("it is raining outside the screen");
        if (Fed < 0.25) parts.Add("a little hungry, but not in a worrying way");
        if (InHammock) parts.Add("cozy in a hammock");
        return parts.Count == 0 ? "sitting on the edge of a window" : string.Join(", ", parts);
    }

    void ApplyFeeling(Feeling feeling)
    {
        switch (feeling)
        {
            case Feeling.Happy:
                Happy.Velocity = 7;
                if (Mode == Mode.Attached && !InHammock) Play(Activity.Wiggle, 1.0);
                break;
            case Feeling.Loving:
                Happy.Velocity = 9;
                ShowEmote(PointerEmote.Hearts, 1.6);
                break;
            case Feeling.Playful:
                Happy.Velocity = 5;
                if (Mode == Mode.Attached && !InHammock) Play(Activity.Dance, 1.4);
                break;
            case Feeling.Curious:
                if (Mode == Mode.Attached && !InHammock) Play(Activity.Curious, 1.3);
                ShowEmote(PointerEmote.Question, 1.0);
                break;
            case Feeling.Agreeing:
                Nod();
                break;
            case Feeling.Shy:
                if (Mode == Mode.Attached && !InHammock) Play(Activity.Look, 1.2);
                Crouch.Velocity = 1.5;
                SlowBlink(0.2);
                break;
            case Feeling.Sleepy:
                Drowsy = Math.Max(Drowsy, 0.55);
                SlowBlink();
                if (Mode == Mode.Attached && !InHammock) Play(Activity.Rest, 1.8);
                break;
            case Feeling.Grumpy:
                if (Mode == Mode.Attached && !InHammock) Play(Activity.Look, 1.0);
                ShakeHead();
                break;
            case Feeling.Surprised:
                Startled.Velocity = 9;
                ShowEmote(PointerEmote.Surprise, 0.7);
                if (Mode == Mode.Attached && !InHammock) Play(Activity.Startle, 0.55);
                break;
            default:
                SlowBlink(0.1);
                break;
        }
    }
}
