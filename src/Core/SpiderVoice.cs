using System.Text;

namespace SpiderBuddy.Core;

/// <summary>How a line feels, and so what the body does while it says it (spec 18.1).</summary>
public enum Feeling { Happy, Loving, Playful, Curious, Agreeing, Shy, Sleepy, Grumpy, Surprised, Calm }

public enum VoiceStatus { Ready, Unavailable, TurnedOff, GettingReady }

/// <summary>The result of talking to the spider.</summary>
public abstract class WordsAnswer
{
    public sealed class Said : WordsAnswer
    {
        public string Text = "";
        public Feeling Feeling;
        public Said(string text, Feeling feeling) { Text = text; Feeling = feeling; }
    }
    public sealed class Declined : WordsAnswer { }
    public sealed class Failed : WordsAnswer { }
}

/// <summary>
/// The platform-independent talking-spider interface (spec 18.1). A backend may be a small
/// local model, Windows AI or a cloud API; the built-in voice is the honest fallback when none
/// is configured. Every prompt carries the same persona and reply rules.
/// </summary>
public interface ISpiderWords
{
    VoiceStatus Status { get; }
    string StatusLabel { get; }
    Task<string?> MuseAsync(SpiderDesign design, string spark, IReadOnlyList<string> avoiding, CancellationToken cancellation = default);
    Task<WordsAnswer> ReplyAsync(SpiderDesign design, string situation, string message,
        IReadOnlyList<(string you, string it)> conversation, CancellationToken cancellation = default);
}

/// <summary>Whole phrases that are shown as written; the model never rewrites these.</summary>
public static class SpiderPhrases
{
    public static readonly IReadOnlyDictionary<string, string[]> Packs = new Dictionary<string, string[]>
    {
        ["chitchat"] = new[]
        {
            "hi!", "boo!", "tap tap… anyone there?", "I'm right here!", "what are you up to?",
            "I'm keeping an eye on things. all eight of them.", "little stretch. big day."
        },
        ["encouragement"] = new[]
        {
            "drink some water", "take a little break…", "you're doing okay", "one thing at a time",
            "sit up straight, friend", "a tiny rest might help"
        },
        ["spider"] = new[]
        {
            "I have eight eyes and still lose my place.", "I can jump fifty times my size. watch this!",
            "my legs are mostly hydraulics, really.", "silk comes out of my back end. it's fine.",
            "I don't need a web to be happy."
        },
        ["verses"] = new[]
        {
            "This is the day which the Lord hath made; we will rejoice and be glad in it. — Psalm 118:24",
            "The Lord is my shepherd; I shall not want. — Psalm 23:1",
            "Be still, and know that I am God. — Psalm 46:10",
            "A friend loveth at all times. — Proverbs 17:17",
            "Let all your things be done with charity. — 1 Corinthians 16:14",
            "The Lord is nigh unto all them that call upon him. — Psalm 145:18",
            "Rejoice evermore. — 1 Thessalonians 5:16"
        }
    };

    public static bool IsVersePack(string pack) =>
        pack is "verses" or "bible" or "Bible verses";

    public static string? RandomLine(SpiderDesign design, Rng rng, bool versesOnly = false)
    {
        var lines = new List<string>();
        foreach (var pack in design.Packs)
        {
            if (versesOnly && !IsVersePack(pack)) continue;
            if (!versesOnly && IsVersePack(pack)) continue;
            if (Packs.TryGetValue(pack, out var set)) lines.AddRange(set);
        }
        if (!versesOnly) lines.AddRange(design.CustomPhrases.Where(p => !string.IsNullOrWhiteSpace(p)));
        return lines.Count == 0 ? null : lines[Math.Min(lines.Count - 1, rng.RangeInt(0, lines.Count))];
    }
}

/// <summary>The voice's shared prompt material, tidying and feeling detector.</summary>
public static class SpiderVoiceText
{
    public static string Persona(SpiderDesign d)
    {
        string name = string.IsNullOrWhiteSpace(d.Name) ? "Spider" : d.Name.Trim();
        var s = new StringBuilder();
        s.AppendLine($"You are {name}, a tiny jumping spider who lives on someone's computer screen as their little pet. " +
            "You walk along the tops of their windows, hang from silk threads, do little dances and nap in a silk hammock.");
        s.AppendLine();
        s.AppendLine("How you talk:");
        s.AppendLine("- Like a sweet, simple little pet: short, everyday words a child would use.");
        s.AppendLine("- Say one clear thing that makes sense. Talk about real, simple things.");
        s.AppendLine("- Cute and a little silly is perfect. Never poetic, deep, dreamy, mysterious or philosophical. No metaphors. Don't describe the scenery.");
        s.AppendLine("- Talk to the person as \"you\" (not \"human\"). They're big and you're the tiny one: never call them tiny or anything silly. Lowercase is fine.");
        s.AppendLine("- No emoji, no hashtags, no quotation marks, no actions in asterisks.");
        s.AppendLine("- You are a spider, not an assistant: never say you are an AI, and don't offer to do tasks. Always kind and fine for all ages.");
        s.AppendLine();
        s.Append(Style(d));
        var topics = d.Packs.Select(Topic).Where(t => t.Length > 0).ToList();
        if (topics.Count > 0) s.AppendLine().Append("You like to talk about: " + string.Join("; ", topics) + ".");
        var yours = d.CustomPhrases.Select(p => p.Trim()).Where(p => p.Length > 0).Take(5).ToList();
        if (yours.Count > 0) s.AppendLine().Append("Things you like to say: " +
            string.Join(", ", yours.Select(p => "\u201C" + p + "\u201D")) + ".");
        return s.ToString();
    }

    static string Topic(string pack) => pack switch
    {
        "chitchat" => "little everyday things",
        "encouragement" => "looking after your person",
        "spider" => "being a spider",
        "verses" => "short kind verses",
        "nature" => "leaves, weather and tiny creatures",
        "food" => "juicy bugs",
        "home" => "your hammock",
        "weather" => "rain, sun and snow",
        "sleepy" => "naps",
        _ => pack
    };

    public static string Style(SpiderDesign d)
    {
        var p = d.Personality;
        var temper = new List<string>();
        void Pick(double v, string low, string high)
        {
            if (v < 0.3) temper.Add(low);
            else if (v > 0.7) temper.Add(high);
        }
        Pick(p.Energy, "slow and yawny (you trail off with \"...\")", "bouncy and excited (lots of exclamation marks!)");
        Pick(p.Curiosity, "not fussed about new things", "curious (you often ask a little question back)");
        Pick(p.Bravery, "shy and a bit nervous (you keep it short, and sometimes say \"um\")", "bold and a bit of a show-off");
        Pick(p.Playfulness, "sensible and plain-spoken", "silly (you love jokes, games and wiggles)");
        Pick(p.Affection, "a little grumpy (short answers, and now and then a \"hmph\"), though secretly fond of them",
            "adoring (you tell them how much you like them)");
        Pick(p.Laziness, "restless, always wanting to go somewhere", "always up for a nap");
        if (temper.Count == 0) temper.Add("friendly and cheerful");
        string s = "Your personality: " + string.Join(", ", temper) + ".";
        string manner = d.Manner.Trim();
        if (manner.Length > 0) s += " Your way of talking: " + manner + " (but still cute and simple).";
        return s;
    }

    public static readonly (string subject, string line)[] MuseExamples =
    {
        ("being hungry", "ooh, I could really go for a fly right now"),
        ("the person", "you've been working so hard. proud of you!"),
        ("the music", "this song makes all eight legs want to dance!"),
        ("the rain", "drip drop! good thing I'm all cozy in here"),
        ("your eyes", "I can see you with all eight eyes. hi!"),
        ("the fact \"I can jump 50 times my length\"", "I can jump fifty times my size. watch this!"),
        ("something fun you did", "I did the biggest jump today. so high!"),
        ("a reminder for the person", "have you had some water lately?"),
        ("feeling sleepy", "yawn... nap time soon, I think"),
        ("the window you are on", "this window is the best seat in the house"),
        ("a game", "bet you can't find me if I hide!"),
        ("it being night", "you're up late! me too, shh"),
        ("your silk hammock", "my hammock is so snuggly. you'd love it"),
        ("the snow", "brr! tiny snowflakes on my fuzzy back")
    };

    public static readonly (string they, string you)[] ReplyExamples =
    {
        ("hey there", "hey! you came to see me!"),
        ("I'm so tired today", "aww. maybe a little nap? I'll keep you company."),
        ("can you sing me a song?", "la la laaa! that's my only song. I'm better at drumming."),
        ("what's 12 times 12?", "um... I can only count to eight. one for each leg!"),
        ("do you love me?", "of course! you're my favourite person in the whole computer."),
        ("you're annoying", "oh. sorry! I'll be extra quiet for a bit."),
        ("I feel sad", "oh no! want a tiny spider hug? I'm right here with you."),
        ("guess what, I passed my test!", "you did?! yay! that calls for a happy dance!"),
        ("is it bedtime?", "yes please. my hammock is calling me. night night!"),
        ("should I eat pizza or pasta?", "pizza! it's round like my eyes."),
        ("tell me a joke", "why are spiders good at the internet? we love the web! hehe"),
        ("what's your favourite colour?", "green, like a leaf to sit on!"),
        ("I have to go to work", "okay! have a good day. I'll guard the screen."),
        ("where do you sleep?", "in my silk hammock up in the corner. it's cosy!"),
        ("are you scared of me?", "nope! you're my big friend.")
    };

    public static string MuseRules(Rng? rng = null)
    {
        var examples = MuseExamples.OrderBy(_ => rng?.Range(0, 1) ?? Random.Shared.NextDouble())
            .Take(5).Select(e => $"About {e.subject}: {e.line}");
        return "Write one thought for the little thought bubble over your head: one short sentence, 3 to 10 words, " +
            "about what you're told to think about.\n\nExamples of good thoughts (the style only; never copy them):\n" +
            string.Join("\n", examples) + "\n\nAnswer with the thought only.";
    }

    public static string ReplyRules(Rng? rng = null)
    {
        var examples = ReplyExamples.OrderBy(_ => rng?.Range(0, 1) ?? Random.Shared.NextDouble())
            .Take(7).Select(e => $"Them: {e.they}\nYou: {e.you}");
        return "The person is talking to you, and you answer in your thought bubble: one or two short sentences, " +
            "20 words at most. Answer exactly what they said or asked, so it makes sense as a reply. " +
            "Only talk about yourself if it fits. The examples show the style only: never copy them, and answer " +
            "in your own personality.\n\nExamples:\n" + string.Join("\n", examples);
    }

    /// <summary>How a line feels, worked out in code from its words (spec 18.1).</summary>
    public static Feeling FeelingOf(string line)
    {
        string l = " " + line.ToLowerInvariant() + " ";
        bool Has(params string[] words) => words.Any(l.Contains);
        if (Has("zz", "sleep", "nap", "night night", "goodnight", "yawn", "bedtime", "hammock is calling")) return Feeling.Sleepy;
        if (Has("hug", "love", "aww", "favourite", "favorite", "proud", "miss you", "right here with you", "oh no")) return Feeling.Loving;
        if (Has("sorry", "oops", " um", "uh,", "shy")) return Feeling.Shy;
        if (Has("grr", "hmph", "no thanks", "nope", "rather not", "leave me")) return Feeling.Grumpy;
        if (Has("?!", "whoa", "wow", "really?", "no way")) return Feeling.Surprised;
        if (Has("hehe", "haha", "dance", "la la", "silly", "play", "wiggle", "jump")) return Feeling.Playful;
        if (Has(" yes", "yes!", "of course", "good idea", "sure", "okay", "agree")) return Feeling.Agreeing;
        if (Has("hmm", "i wonder") || line.TrimEnd().EndsWith('?')) return Feeling.Curious;
        if (line.Contains('!')) return Feeling.Happy;
        return Feeling.Calm;
    }

    /// <summary>The feeling tag an answer starts with, and the rest of the line.</summary>
    public static (Feeling feeling, string text) FeelingIn(string raw)
    {
        string text = raw.Trim();
        Feeling found = Feeling.Calm;
        int open = text.IndexOf('[');
        if (open >= 0 && open < 12)
        {
            int close = text.IndexOf(']', open);
            if (close > open)
            {
                string word = text[(open + 1)..close].Trim().ToLowerInvariant();
                var parsed = Enum.GetValues<Feeling>().FirstOrDefault(f => f.ToString().ToLowerInvariant() == word);
                if (Enum.GetValues<Feeling>().Any(f => f.ToString().ToLowerInvariant() == word)) found = parsed;
                text = text.Remove(open, close - open + 1);
            }
        }
        while (true)
        {
            open = text.IndexOf('[');
            if (open < 0) break;
            int close = text.IndexOf(']', open);
            if (close < 0 || close - open >= 14) break;
            text = text.Remove(open, close - open + 1);
        }
        return (found, text.Trim());
    }

    /// <summary>Plain words for a bubble: no labels, quotes, actions or breaks; cut at a word.</summary>
    public static string? Clean(string raw, string name, int most)
    {
        string text = raw.Replace("\r", " ").Replace("\n", " ");
        while (true)
        {
            int a = text.IndexOf('*');
            if (a < 0) break;
            int b = text.IndexOf('*', a + 1);
            if (b < 0) break;
            text = text.Remove(a, b - a + 1);
        }
        // A small model can still emit a hashtag or an emoji even when told not to. Keep the
        // bubble plain by dropping the tag and any non-BMP/dingbat symbol.
        while (true)
        {
            int hash = text.IndexOf('#');
            if (hash < 0) break;
            int end = hash;
            while (end < text.Length && !char.IsWhiteSpace(text[end])) end++;
            text = text.Remove(hash, end - hash);
        }
        var plain = new StringBuilder(text.Length);
        for (int i = 0; i < text.Length; i++)
        {
            char c = text[i];
            if (char.IsHighSurrogate(c)) { i++; continue; }
            if (char.IsLowSurrogate(c) || c == '\uFE0F' || c is >= '\u2600' and <= '\u27BF') continue;
            plain.Append(c);
        }
        text = plain.ToString().Trim();
        string spider = string.IsNullOrWhiteSpace(name) ? "Spider" : name.Trim();
        foreach (string label in new[] { "You:", "Thought:", spider + ":", "Me:" })
        {
            if (text.StartsWith(label, StringComparison.OrdinalIgnoreCase))
                text = text[label.Length..].Trim();
        }
        text = text.Trim('"', '\u201C', '\u201D', '\'', '\u2018', '\u2019', '`', ' ', '\t');
        text = string.Join(" ", text.Split(' ', StringSplitOptions.RemoveEmptyEntries));
        if (text.Length == 0) return null;
        if (text.Length > most)
        {
            string cut = text[..most];
            int end = cut.LastIndexOfAny(new[] { '.', '!', '?' });
            if (end > most / 2) text = cut[..(end + 1)];
            else
            {
                int space = cut.LastIndexOf(' ');
                text = space > 0 ? cut[..space] + "…" : cut + "…";
            }
        }
        return text;
    }
}

/// <summary>
/// A tiny always-available companion voice. It is not a language model: Stage 18 calls for an
/// honest status, and this is labelled as the built-in voice wherever it is selected.
/// </summary>
public sealed class BuiltInSpiderWords : ISpiderWords
{
    readonly Rng _rng;
    readonly object _gate = new();

    public BuiltInSpiderWords(ulong? seed = null) => _rng = new Rng(seed ?? (ulong)Environment.TickCount64);

    public VoiceStatus Status => VoiceStatus.Ready;
    public string StatusLabel => "Built-in voice";

    public Task<string?> MuseAsync(SpiderDesign design, string spark, IReadOnlyList<string> avoiding,
        CancellationToken cancellation = default)
    {
        string l = spark.ToLowerInvariant();
        string[] choices = l switch
        {
            var s when s.Contains("bug") || s.Contains("fly") => new[]
            {
                "ooh, is that a fly? I could go for a little snack.",
                "I saw something wiggly. better go and look!",
                "shh... I'm being a very still leaf."
            },
            var s when s.Contains("music") => new[]
            {
                "this song makes all eight legs want to dance!",
                "I like this one. tap tap tap!",
                "can we keep this song on for a bit?"
            },
            var s when s.Contains("rain") || s.Contains("storm") => new[]
            {
                "drip drop! good thing I'm all cozy in here.",
                "that thunder is very big. I'm still brave. mostly.",
                "rain makes the glass all shiny."
            },
            var s when s.Contains("snow") => new[]
            {
                "brr! tiny snowflakes on my fuzzy back.",
                "the snow makes everything quiet.",
                "I could make a tiny snow spider. maybe later."
            },
            var s when s.Contains("sun") => new[]
            {
                "this warm spot is the best spot.",
                "the sun feels nice on my eight eyes.",
                "a little bask, then back to work. spider work."
            },
            var s when s.Contains("person") => new[]
            {
                "you've been working so hard. proud of you!",
                "hello! I'm right here if you need a tiny friend.",
                "have you had some water lately?"
            },
            var s when s.Contains("hungry") => new[]
            {
                "ooh, I could really go for a fly right now.",
                "my tummy is doing a tiny rumble.",
                "is it snack time? it feels like snack time."
            },
            var s when s.Contains("hammock") => new[]
            {
                "my hammock is so snuggly. you'd love it.",
                "a nap in the corner sounds very good.",
                "I put extra silk in the cozy bit."
            },
            var s when s.Contains("night") => new[]
            {
                "you're up late! me too, shh.",
                "the screen is extra glowy at night.",
                "night night. I'll keep one eye open. or eight."
            },
            _ => new[]
            {
                "just checking on you. all good?",
                "I'm doing a little think.",
                "this seems like a nice place to sit.",
                "tiny steps, big adventure."
            }
        };
        string line;
        lock (_gate)
        {
            var fresh = choices.Where(c => !avoiding.Contains(c, StringComparer.OrdinalIgnoreCase)).ToArray();
            line = (fresh.Length > 0 ? fresh : choices)[Math.Min((fresh.Length > 0 ? fresh : choices).Length - 1,
                _rng.RangeInt(0, (fresh.Length > 0 ? fresh : choices).Length))];
        }
        return Task.FromResult<string?>(SpiderVoiceText.Clean(line, design.Name, 80));
    }

    public Task<WordsAnswer> ReplyAsync(SpiderDesign design, string situation, string message,
        IReadOnlyList<(string you, string it)> conversation, CancellationToken cancellation = default)
    {
        string raw = ReplyTo(message, design);
        string? line = SpiderVoiceText.Clean(raw, design.Name, 150);
        return Task.FromResult<WordsAnswer>(line is null
            ? new WordsAnswer.Failed()
            : new WordsAnswer.Said(line, SpiderVoiceText.FeelingOf(line)));
    }

    string ReplyTo(string message, SpiderDesign d)
    {
        string m = message.Trim().ToLowerInvariant();
        string name = string.IsNullOrWhiteSpace(d.Name) ? "your spider" : d.Name;
        bool Has(params string[] words) => words.Any(m.Contains);

        if (Has("hello", "hey", "hi ", "hi!", "hiya", "morning", "good evening")) return "hey! you came to see me!";
        if (Has("how are you", "you okay", "how's it going")) return "I'm good! my legs are all working and everything.";
        if (Has("tired", "exhausted", "sleepy", "long day")) return "aww. maybe a little nap? I'll keep you company.";
        if (Has("sad", "upset", "crying", "bad day", "lonely")) return "oh no! want a tiny spider hug? I'm right here with you.";
        if (Has("love you", "do you love", "like me")) return "of course! you're my favourite person in the whole computer.";
        if (Has("hug")) return "tiny spider hug! all eight arms. careful, I'm fuzzy.";
        if (Has("joke", "funny")) return "why are spiders good at the internet? we love the web! hehe";
        if (Has("sing", "song")) return "la la laaa! that's my only song. I'm better at drumming.";
        if (Has("math", "times", "plus", "minus", "calculate")) return "um... I can only count to eight. one for each leg!";
        if (Has("bed", "sleep", "goodnight", "night night")) return "yes please. my hammock is calling me. night night!";
        if (Has("food", "hungry", "snack", "pizza", "pasta", "eat")) return "ooh! I vote for anything tiny and wiggly. or pizza. pizza is good too.";
        if (Has("work", "meeting", "study", "exam")) return "okay! have a good day. I'll guard the screen.";
        if (Has("name", "who are you")) return $"I'm {name}! I'm the tiny spider living on your screen.";
        if (Has("thank")) return "you're welcome! that made my palps wiggle.";
        if (Has("sorry")) return "it's okay! I'm not upset. look, I'm doing a little dance.";
        if (Has("bye", "goodbye", "see you")) return "bye! I'll be right here when you get back.";
        if (Has("what are you doing", "what's up", "what doing")) return "just sitting on this edge and looking at you. it's a good job.";
        if (m.EndsWith('?')) return "hmm, I'm not sure! but I'm glad you asked me.";
        if (Has("you're annoying", "shut up", "go away")) return "oh. sorry! I'll be extra quiet for a bit.";
        if (Has("good", "great", "yay", "passed", "won")) return "yay! that calls for a happy dance!";
        return "I'm listening! tell me a bit more.";
    }
}
