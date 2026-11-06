namespace SpiderBuddy.Core;

/// <summary>Intentional wandering: roaming about vs pottering at one thing (spec 6.2).</summary>
public enum Mood { Roam, Potter }

/// <summary>
/// Stage 6 — the brain. A decision clock, the priority list, the weighted repertoire, moods,
/// heading commitment, thoughts and the body-language manner of each outing.
/// </summary>
public sealed partial class Spider
{
    public double DecisionIn = 2.0;
    public Mood Mood = Mood.Roam;
    public double MoodUntil = 30;
    public double Linger = 1;
    public bool MayTurnBack => KeepHeadingFor <= 0;
    public double Drowsy, Chill = 1, Hunger;
    public Activity PreviousActivity = Activity.Idle;
    public ThoughtKind CurrentThought { get; private set; }
    public string? CurrentThoughtText { get; private set; }
    public int DirectionFlips { get; private set; }
    public int QuickReturns { get; private set; }
    public int Decisions { get; private set; }
    public double LastDecisionAt { get; private set; } = -99;

    /// <summary>Harnesses that command activities themselves switch the brain off (spec 4.9).</summary>
    public static bool BrainDefault = true;
    public bool BrainEnabled = BrainDefault;

    double _thoughtFrom, _thoughtUntil = -99;
    double _lastFlipAt = -99;
    bool _sneaking;
    GaitStyle _boutStyle = GaitStyle.Normal;

    // Mood weights (spec 6.2). Undersides always count as roam, so the caller may force it.
    double GoW => Mood == Mood.Potter ? 0.15 : 2.4;
    double SitW => Mood == Mood.Potter ? 1.3 : 0.5;
    double ShowW => Mood == Mood.Potter ? 1.7 : 0.85;
    double AwayW => Mood == Mood.Potter ? 0.3 : 1.3;

    /// <summary>The whole brain tick: clock, mood, thought expiry, finishing and deciding.</summary>
    public void UpdateBrain(double dt)
    {
        if (!BrainEnabled || Mode != Mode.Attached) return;
        if (Listening) return;

        if (KeepHeadingFor > 0) KeepHeadingFor -= dt;
        if (Time > MoodUntil) NextMood();
        if (Time > _thoughtUntil) { CurrentThought = ThoughtKind.None; CurrentThoughtText = null; }

        if (Activity != Activity.Idle && ActivityTime >= ActivityDur) FinishActivity();

        if (Activity == Activity.Idle)
        {
            DecisionIn -= dt * Design.Personality.Liveliness * M.Lerp(1, 0.55, Drowsy) * BoxDecisionScale;
            if (DecisionIn <= 0) Think();
        }
    }

    public void SetMood(Mood mood)
    {
        Mood = mood;
        MoodUntil = Time + (mood == Mood.Potter ? Rng.Range(15, 35) : Rng.Range(20, 50));
        Linger = mood == Mood.Potter ? Rng.Range(1.4, 2.2) : 1;
    }

    void NextMood() => SetMood(Rng.Chance(0.45) ? Mood.Potter : Mood.Roam);

    /// <summary>An activity ran its course: idle, a look at where it just arrived, and a whim beat.</summary>
    public void FinishActivity()
    {
        Activity was = Activity;
        PreviousActivity = was;
        // A queued follow-through (a celebration's wiggle) belongs to the activity that just ended.
        if (_pointerQueued is { } queued)
        {
            _pointerQueued = null;
            Play(queued.activity, queued.duration);
            return;
        }
        if (PendingJump is { } target)
        {
            PendingJump = null;
            LaunchJump(target);
            return;
        }
        Activity = Activity.Idle;
        ActivityTime = 0;
        ActivityDur = 1;
        if (was is Activity.Walk or Activity.Sneak or Activity.Scurry) AfterWalk();
        if (was != Activity.Sleep)
            DecisionIn = Math.Max(DecisionIn, Rng.Range(0.8, 2.0) * Math.Max(0.25, Design.Personality.Liveliness));
    }

    /// <summary>A walk is for something: 30% look, 15% glance, 10% peer, 7% groom (spec 6.3).</summary>
    void AfterWalk()
    {
        double r = Rng.Range(0, 1);
        if (r < 0.30) Play(Activity.Look, Rng.Range(0.7, 1.6) * Linger);
        else if (r < 0.45) Play(Activity.Glance, Rng.Range(0.8, 1.4) * Linger);
        else if (r < 0.55) Play(Activity.Peer, Rng.Range(1.2, 1.8) * Linger);
        else if (r < 0.62) Play(Activity.Groom, Rng.Range(1.4, 2.4) * Linger);
    }

    /// <summary>The priority list of spec 6.2, first match wins; the rest is the weighted draw.</summary>
    public void Think()
    {
        if (Box is { } box && !box.Contains(Pos)) { ReturnToBox(); return; }
        Decisions++;
        LastDecisionAt = Time;
        DecisionIn = Rng.Range(1.0, 3.4) / Math.Max(0.25, Design.Personality.Liveliness);
        var p = ActivePersonality;

        // 19. Sleep, once idle long enough (or the dial dialled up).
        double sleepAfter = M.Lerp(120, 20, p.Laziness) * M.Lerp(1, 0.35, Drowsy) * (1 + 2 * Hunger);
        if ((IdleFor > sleepAfter && Rng.Chance(Math.Min(1,
                M.Lerp(0.1, 0.6, p.Laziness) * M.Lerp(1, 1.8, Drowsy))))
            || Design.Habits.Sleep >= 0.995)
        {
            Play(Activity.Sleep, Rng.Range(40, 120) * (0.7 + p.Laziness));
            return;
        }

        // 21. A pointer trip in progress: go and look, when it is worth the walk.
        if (ApproachCursor && Interest > 0.5 && CursorFree
            && Cursor.DistanceTo(Pos) > 70 * Scale && CursorStillFor > 0.4)
        {
            int dir = Cursor.X >= Pos.X ? 1 : -1;
            TurnTo(dir);
            WalkSpeedScale = M.Lerp(0.85, 1.15, Rng.Range(0, 1));
            Play(Activity.Walk, Rng.Range(1.5, 3.0));
            return;
        }

        // 20. Something worth hunting (spec 10.3), before leisure and before peek-a-boo.
        if (PreyHunt == HuntStage.None && FindQuarry() is { } quarry
            && quarry.Pos.DistanceTo(Pos) < 420 * Scale
            && Rng.Chance(0.45 + 0.45 * Prowess))
        {
            StartHunt(quarry);
            return;
        }

        // 21. A toy left lying about still gets batted now and then (spec 11.3).
        if (MaybePlayWithToy()) return;

        // 22. Peek-a-boo, when someone is about and there is an edge to hide behind (spec 9).
        if (MaybePeekaboo()) return;

        if (Interest > 0.5) PickAttention();
        else PickLeisure();
    }

    void Choose(List<(double weight, Action action)> options)
    {
        var weights = new List<double>(options.Count);
        foreach (var (w, _) in options) weights.Add(w);
        int i = Rng.WeightedIndex(weights);
        // WeightedIndex returns 0 for an all-zero hat; that entry is itself weightless.
        if (options.Count == 0 || options[i].weight <= 0) return;
        options[i].action();
    }

    /// <summary>The attention set: the pointer has its attention (spec 6.3).</summary>
    void PickAttention()
    {
        var p = ActivePersonality;
        var h = Design.Habits;
        double love = p.Love;
        double play = p.Play(Chill, Drowsy);
        var o = new List<(double, Action)>
        {
            (10 * Habits.Weight(h.Look), () => Play(Activity.Look, Rng.Range(1.4, 3.0))),
            (6 * M.Lerp(0.6, 1.4, p.Curiosity) * Habits.Weight(h.Stare), () => Play(Activity.Stare, Rng.Range(2.5, 5))),
            (5 * M.Lerp(0.5, 1.5, p.Curiosity) * Habits.Weight(h.Curious), () => Play(Activity.Curious, Rng.Range(1.2, 2.2))),
            (4 * love * Habits.Weight(h.Greet), () => { Play(Activity.Greet, Rng.Range(1.6, 2.4)); Happy.Velocity = 4; }),
            (3 * play * Habits.Weight(h.ArmsUp), () => Play(Activity.ArmsUp, Rng.Range(0.9, 1.4))),
            (2 * love * Habits.Weight(h.Wave), () => Play(Activity.Wave, 1.5)),
            (3 * Habits.Weight(h.Fidget), () => Play(Activity.Fidget, Rng.Range(0.7, 1.2))),
            (2 * Habits.Weight(h.Peer), () => Play(Activity.Peer, Rng.Range(1.0, 1.6))),
        };
        Choose(o);
    }

    /// <summary>The out-and-about repertoire of spec 6.3.</summary>
    void PickLeisure()
    {
        var p = ActivePersonality;
        var h = Design.Habits;
        double busy = p.Busy(Chill, Drowsy);
        double lazy = p.Lazy(Chill, Drowsy);
        double love = p.Love;
        double play = p.Play(Chill, Drowsy);
        bool pointerNear = Time - _lastUserActivity < 30 && Cursor.DistanceTo(Pos) < 520 * Scale;
        bool pointerAround = Time - _lastUserActivity < 40 && Cursor.DistanceTo(Pos) < 560 * Scale;
        bool onTop = Map.Loop(Anchor.LoopId)?.SegAt(Anchor.SegIdx) is { } seg && seg.Normal.Y > 0.5;

        var o = new List<(double, Action)>
        {
            (30 * busy * Habits.Weight(h.Wander) * GoW, WanderBout),
            (10 * Habits.Weight(h.Look) * SitW, () => Play(Activity.Look, Rng.Range(0.7, 2.2) * Linger)),
            (6 * lazy * Habits.Weight(h.Rest) * SitW, () => Play(Activity.Rest, Rng.Range(3, 8) * Linger)),
            (6 * Habits.Weight(h.Groom) * SitW, () => Play(Activity.Groom, Rng.Range(1.4, 2.8) * Linger)),
            (6 * (0.5 + busy * 0.5) * Habits.Weight(h.Fidget) * SitW, () => Play(Activity.Fidget, Rng.Range(0.7, 1.2))),
            (4 * Habits.Weight(h.Scratch) * SitW, () => Play(Activity.Scratch, Rng.Range(1.0, 1.6) * Linger)),
            (2 * love * Habits.Weight(h.Wave) * ShowW, () => Play(Activity.Wave, 1.5)),
            (2 * play * Habits.Weight(h.Wiggle) * ShowW, () => Play(Activity.Wiggle, 0.8)),
            (3 * love * Habits.Weight(h.Glance) * SitW, () => Play(Activity.Glance, Rng.Range(0.8, 1.6))),
            (4 * M.Lerp(0.5, 1.5, p.Curiosity) * Habits.Weight(h.Muse) * SitW, Muse),
            (1.4 * M.Lerp(0.5, 1.5, p.Curiosity) * M.Lerp(0.6, 1.4, p.Playfulness) * Habits.Weight(h.Glance),
                () => Play(Activity.DoubleTake, 1.4)),
            (1.2 * M.Lerp(0.4, 1.8, p.Laziness) * M.Lerp(1, 1.6, Drowsy) * Habits.Weight(h.Rest) * SitW,
                () => Play(Activity.Sigh, Rng.Range(1.8, 2.4))),
            (2.5 * play * M.Lerp(0.6, 1.4, p.Energy) * Habits.Weight(h.Drum) * ShowW,
                () => { Play(Activity.Drum, Rng.Range(2.9, 5.8)); ShowEmote(PointerEmote.Note, 2.0); }),
            (3 * M.Lerp(0.4, 1.8, p.Curiosity) * Habits.Weight(h.Peer) * SitW, () => Play(Activity.Peer, Rng.Range(1.2, 2.0))),
            (2.5 * M.Lerp(0.5, 1.5, (p.Affection + p.Bravery) / 2) * Habits.Weight(h.ArmsUp) * ShowW,
                () => Play(Activity.ArmsUp, Rng.Range(0.9, 1.5))),
            (1.5 * play * Habits.Weight(h.Dance) * ShowW, () => Play(Activity.Dance, Rng.Range(1.2, 2.0))),
            (1.5 * busy * Habits.Weight(h.Pushup) * ShowW, () => Play(Activity.Pushup, Rng.Range(1.2, 1.8))),
            (1.5 * (0.5 + lazy * 0.5) * Habits.Weight(h.Stretch) * SitW, () => Play(Activity.LegStretch, 1.6)),
            (1 * play * Habits.Weight(h.Spin) * ShowW, () => Play(Activity.Spin, 1.6)),
        };
        if (pointerNear) o.Add((3 * love * Habits.Weight(h.Greet) * ShowW, () => Play(Activity.Greet, Rng.Range(1.8, 2.6))));
        if (pointerAround) o.Add((3 * love * M.Lerp(0.6, 1.4, p.Curiosity) * Habits.Weight(h.Stare) * SitW,
            () => Play(Activity.Stare, Rng.Range(3, 7))));
        // Roll only on top of something (spec 6.3).
        if (onTop) o.Add((2 * play * Habits.Weight(h.Roll) * ShowW, () => Play(Activity.Roll, Rng.Range(1.5, 1.9))));
        // Looking back is only offered while the heading commitment allows it.
        if (MayTurnBack) o.Add((2 * Habits.Weight(h.Look) * SitW, LookBack));

        Choose(o);
    }

    void Muse()
    {
        Play(Activity.Muse, 2.0 * Linger);
        _thoughtFrom = Time;
        _thoughtUntil = Time + 3.2;
        if (TryTalkingMuse()) return;
        if (Design.CustomPhrases.Count > 0 && Rng.Chance(0.35))
        {
            CurrentThought = ThoughtKind.Text;
            CurrentThoughtText = Design.CustomPhrases[Math.Min(Design.CustomPhrases.Count - 1,
                (int)Rng.Range(0, Design.CustomPhrases.Count))];
        }
        else
        {
            CurrentThought = ThoughtKind.Heart;
            CurrentThoughtText = null;
        }
    }

    void LookBack()
    {
        TurnTo(-WalkDir);
        Play(Activity.Look, Rng.Range(1.0, 1.8) * Linger);
    }

    /// <summary>A walk bout: manner, direction, pace and duration picked for the whole outing.</summary>
    void WanderBout()
    {
        var p = Design.Personality;
        _sneaking = Rng.Chance(M.Lerp(0.3, 0.05, p.Bravery));
        bool hurried = Rng.Chance(M.Lerp(0.04, 0.22, p.Energy) * M.Lerp(1, 0.2, Drowsy));
        _boutStyle = Design.Gait.Preference switch
        {
            GaitPreference.Bouncy => GaitStyle.Bouncy,
            GaitPreference.Tiptoe => GaitStyle.Tiptoe,
            GaitPreference.Lumbering => GaitStyle.Lumber,
            GaitPreference.Scurrying => GaitStyle.Normal,
            _ => (GaitStyle)Rng.WeightedIndex(new double[] { 2, 1, 1, 1 }),
        };
        WalkSpeedScale = M.Lerp(0.85, 1.15, (Design.Gait.Pace - 0.5) * 2 + Rng.Range(-0.2, 0.2) + 0.5);
        TurnTo(WanderWay());
        double dur = hurried ? Rng.Range(0.5, 1.2) : Rng.Range(1.4, 5.0);
        if (Mood == Mood.Potter) dur = Math.Min(dur, Rng.Range(0.7, 1.6));
        Play(_sneaking ? Activity.Sneak : hurried ? Activity.Scurry : Activity.Walk, dur);
    }

    public GaitStyle BoutStyle => _boutStyle;
    public bool BoutSneaks => _sneaking;

    /// <summary>Turn the body round to face a direction, committing to it so it does not dither.</summary>
    public void TurnTo(int dir)
    {
        dir = dir >= 0 ? 1 : -1;
        if (dir == WalkDir) return;
        WalkDir = dir;
        DirectionFlips++;
        if (Time - _lastFlipAt < 2.0) QuickReturns++;
        _lastFlipAt = Time;
        KeepHeadingFor = Rng.Range(6, 14);
    }

    /// <summary>
    /// The way it would set off: its commitment first, and only then whether there is room. On a closed
    /// loop there always is, so a walk never reverses without a reason (spec 6.2).
    /// </summary>
    public int WanderWay()
    {
        if (MayTurnBack || RoomAhead(WalkDir)) return WalkDir;
        return RoomAhead(-WalkDir) ? -WalkDir : WalkDir;
    }

    public bool RoomAhead(int dir)
    {
        var loop = Map.Loop(Anchor.LoopId);
        if (loop is null || loop.Segs.Count == 0) return false;
        if (loop.Closed) return true;
        var seg = loop.Segs[Math.Min(Anchor.SegIdx, loop.Segs.Count - 1)];
        double room = dir > 0 ? seg.Len - Anchor.T : Anchor.T;
        if (room > 40 * Scale) return true;
        return dir > 0 ? Anchor.SegIdx < loop.Segs.Count - 1 : Anchor.SegIdx > 0;
    }

    /// <summary>The look a thought wears, when one is showing.</summary>
    public bool ThoughtShowing => CurrentThought != ThoughtKind.None && Time < _thoughtUntil && !Cinema;
    public double ThoughtT => ThoughtShowing
        ? M.Clamp01((Time - _thoughtFrom) / Math.Max(0.001, _thoughtUntil - _thoughtFrom))
        : 0;
}
