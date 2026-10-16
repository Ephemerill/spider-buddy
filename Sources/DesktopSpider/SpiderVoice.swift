import Foundation
#if canImport(FoundationModels)
// Weakly linked: the framework is only there on macOS 26 and later, and the
// app still runs on 13 (where it keeps to its phrases).
@_weakLinked import FoundationModels
#endif

// MARK: - Its own words
//
// With "Its Own Words" picked in the Studio's Thoughts tab, what it thinks
// is written for the moment by Apple Intelligence's on-device model, in the
// spider's own character — its name, its temperament, how you said it
// talks, the things it likes to talk about — and you can click its bubble
// to talk back (see ChatPanel.swift). Nothing leaves the Mac.
//
// Every call is a fresh session: the conversation so far is handed over in
// the prompt (a few short exchanges), which keeps well inside the model's
// context and means nothing is left over from one spider design to the next.

final class SpiderVoice: SpiderWords {
    var status: VoiceStatus {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(let why):
                switch why {
                case .appleIntelligenceNotEnabled: return .turnedOff
                case .modelNotReady: return .gettingReady
                case .deviceNotEligible: return .notThisMac
                @unknown default: return .gettingReady
                }
            }
        }
        #endif
        return .needsNewerMacOS
    }

    /// Gets the model loaded ahead of a conversation, so the first answer
    /// is not the slow one.
    func prewarm(as design: SpiderDesign) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), status == .ready {
            LanguageModelSession(instructions: SpiderVoice.persona(design) + "\n\n" + SpiderVoice.replyRules).prewarm()
        }
        #endif
    }

    func muse(as design: SpiderDesign, about spark: String, avoiding: [String], done: @escaping (String?) -> Void) {
        var prompt = ""
        if !avoiding.isEmpty {
            prompt += "You said these lately, so don't say them again: " + avoiding.suffix(5).map { "\u{201C}\($0)\u{201D}" }.joined(separator: "; ") + "\n"
        }
        prompt += "Now write one thought about: \(spark)\n\(SpiderVoice.style(design)) Use your own words, not the examples'."
        generate(instructions: SpiderVoice.persona(design) + "\n\n" + SpiderVoice.museRules, prompt: prompt,
                 temperature: 0.8, tokens: 40) { outcome in
            if case .text(let raw) = outcome { done(SpiderVoice.clean(SpiderVoice.feeling(in: raw).1, name: design.name, most: 80)) } else { done(nil) }
        }
    }

    func reply(as design: SpiderDesign, situation: String, to message: String,
               after conversation: [(you: String, it: String)], done: @escaping (WordsAnswer) -> Void) {
        var prompt = "(Background, don't bring it up unless they ask: \(situation).)\n\n"
        if !conversation.isEmpty {
            prompt += "The conversation so far:\n"
            for (you, it) in conversation { prompt += "Them: \(you)\nYou: \(it)\n" }
        }
        prompt += "(\(SpiderVoice.style(design)) Answer in your own words; the examples only show the style.)\n"
        prompt += "Them: \(message)\nYou:"
        generate(instructions: SpiderVoice.persona(design) + "\n\n" + SpiderVoice.replyRules, prompt: prompt,
                 temperature: 0.7, tokens: 70) { outcome in
            switch outcome {
            case .text(let raw):
                if let line = SpiderVoice.clean(SpiderVoice.feeling(in: raw).1, name: design.name, most: 150) {
                    done(.said(line, SpiderVoice.feeling(of: line)))
                } else {
                    done(.failed)
                }
            case .declined: done(.declined)
            case .failed: done(.failed)
            }
        }
    }

    // MARK: The model

    private enum Outcome { case text(String), declined, failed }

    /// One answer from the model, back on the main thread; given up on after
    /// 20 seconds.
    private func generate(instructions: String, prompt: String, temperature: Double, tokens: Int,
                          done: @escaping (Outcome) -> Void) {
        var finished = false
        let finish: (Outcome) -> Void = { o in
            guard !finished else { return }
            finished = true
            done(o)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), status == .ready {
            let task = Task { @MainActor in
                let session = LanguageModelSession(instructions: instructions)
                do {
                    let r = try await session.respond(to: prompt, options: GenerationOptions(temperature: temperature, maximumResponseTokens: tokens))
                    finish(.text(r.content))
                } catch let e as LanguageModelSession.GenerationError {
                    switch e {
                    case .guardrailViolation, .refusal: finish(.declined)
                    default: finish(.failed)
                    }
                } catch {
                    finish(.failed)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                guard !finished else { return }
                task.cancel()
                finish(.failed)
            }
            return
        }
        #endif
        DispatchQueue.main.async { finish(.failed) }
    }

    // MARK: Who it is
    //
    // The on-device model is small: told to be a spider, it goes misty and
    // poetic ("vibrations dance in the air…"). What keeps it cute and
    // making sense is a plain picture of the voice — a sweet little pet,
    // everyday words, one clear thing — worked examples to copy, and, for a
    // passing thought, one concrete thing to think about (`Spider.spark`).

    /// The spider, told to the model: who it is, how it talks, its temper.
    static func persona(_ d: SpiderDesign) -> String {
        let name = d.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Spider" : d.name
        var s = """
        You are \(name), a tiny jumping spider who lives on someone's computer screen as their little pet. \
        You walk along the tops of their windows, hang from silk threads, do little dances and nap in a silk hammock.

        How you talk:
        - Like a sweet, simple little pet: short, everyday words a child would use.
        - Say one clear thing that makes sense. Talk about real, simple things.
        - Cute and a little silly is perfect. Never poetic, deep, dreamy, mysterious or philosophical. No metaphors. Don't describe the scenery.
        - Talk to the person as "you" (not "human"). They're big and you're the tiny one: never call them tiny or anything silly. Lowercase is fine.
        - No emoji, no hashtags, no quotation marks, no actions in asterisks.
        - You are a spider, not an assistant: never say you are an AI, and don't offer to do tasks. Always kind and fine for all ages.

        \(style(d))
        """
        let topics = d.packs.map(\.topic)
        if !topics.isEmpty { s += "\nYou like to talk about: " + topics.joined(separator: "; ") + "." }
        let yours = d.customPhrases.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(5)
        if !yours.isEmpty { s += "\nThings you like to say: " + yours.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ") + "." }
        return s
    }

    /// Its temper, and how you said it talks: said in the instructions, and
    /// again right by each request (a small model heeds what is nearest).
    static func style(_ d: SpiderDesign) -> String {
        let p = d.personality
        var temper: [String] = []
        func pick(_ v: CGFloat, low: String, high: String) {
            if v < 0.3 { temper.append(low) } else if v > 0.7 { temper.append(high) }
        }
        // Each as how it sounds, which a small model can follow, rather
        // than a bare adjective, which it mostly ignores.
        pick(p.energy, low: "slow and yawny (you trail off with \"...\")", high: "bouncy and excited (lots of exclamation marks!)")
        pick(p.curiosity, low: "not fussed about new things", high: "curious (you often ask a little question back)")
        pick(p.bravery, low: "shy and a bit nervous (you keep it short, and sometimes say \"um\")", high: "bold and a bit of a show-off")
        pick(p.playfulness, low: "sensible and plain-spoken", high: "silly (you love jokes, games and wiggles)")
        pick(p.affection, low: "a little grumpy (short answers, and now and then a \"hmph\"), though secretly fond of them",
             high: "adoring (you tell them how much you like them)")
        pick(p.laziness, low: "restless, always wanting to go somewhere", high: "always up for a nap")
        if temper.isEmpty { temper = ["friendly and cheerful"] }
        var s = "Your personality: \(temper.joined(separator: ", "))."
        let manner = d.manner.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manner.isEmpty { s += " Your way of talking: \(manner) (but still cute and simple)." }
        return s
    }

    /// What a passing thought is, with a few examples drawn from a larger
    /// set each time (always the same few, and it copies their openings).
    private static var museRules: String {
        let examples = museExamples.shuffled().prefix(5).map { "About \($0.0): \($0.1)" }.joined(separator: "\n")
        return """
        Write one thought for the little thought bubble over your head: one short sentence, 3 to 10 words, about what you're told to think about.

        Examples of good thoughts (the style only; never copy them):
        \(examples)

        Answer with the thought only.
        """
    }

    private static let museExamples: [(String, String)] = [
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
        ("the snow", "brr! tiny snowflakes on my fuzzy back"),
    ]

    /// What an answer is, with examples drawn the same way.
    private static var replyRules: String {
        let examples = replyExamples.shuffled().prefix(7).map { "Them: \($0.0)\nYou: \($0.1)" }.joined(separator: "\n")
        return """
        The person is talking to you, and you answer in your thought bubble: one or two short sentences, 20 words at most. \
        Answer exactly what they said or asked, so it makes sense as a reply. Only talk about yourself if it fits. \
        The examples show the style only: never copy them, and answer in your own personality.

        Examples:
        \(examples)
        """
    }

    private static let replyExamples: [(String, String)] = [
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
        ("are you scared of me?", "nope! you're my big friend."),
    ]

    // MARK: Tidying what comes back

    /// How an answer feels, by its words: what its body does as it says it.
    static func feeling(of line: String) -> Feeling {
        let l = " " + line.lowercased() + " "
        func has(_ words: [String]) -> Bool { words.contains { l.contains($0) } }
        if has(["zz", "sleep", "nap", "night night", "goodnight", "yawn", "bedtime", "hammock is calling"]) { return .sleepy }
        if has(["hug", "love", "aww", "favourite", "favorite", "proud", "miss you", "right here with you", "oh no"]) { return .loving }
        if has(["sorry", "oops", " um", "uh,", "shy"]) { return .shy }
        if has(["grr", "hmph", "no thanks", "nope", "rather not", "leave me"]) { return .grumpy }
        if has(["?!", "whoa", "wow", "really?", "no way"]) { return .surprised }
        if has(["hehe", "haha", "dance", "la la", "silly", "play", "wiggle", "jump"]) { return .playful }
        if has([" yes", "yes!", "of course", "good idea", "sure", "okay", "agree"]) { return .agreeing }
        if has(["hmm", "i wonder"]) || line.hasSuffix("?") { return .curious }
        if line.contains("!") { return .happy }
        return .calm
    }

    /// The feeling tag the answer starts with, and the rest of it.
    static func feeling(in raw: String) -> (Feeling, String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var found: Feeling = .calm
        if let open = text.firstIndex(of: "["), let close = text[open...].firstIndex(of: "]"),
           text.distance(from: text.startIndex, to: open) < 12 {
            let word = text[text.index(after: open)..<close].trimmingCharacters(in: .whitespaces).lowercased()
            if let f = Feeling(rawValue: word) { found = f }
            text.removeSubrange(open...close)
        }
        // (Any more tags along the way go too.)
        while let open = text.firstIndex(of: "["), let close = text[open...].firstIndex(of: "]"),
              text.distance(from: open, to: close) < 14 {
            text.removeSubrange(open...close)
        }
        return (found, text)
    }

    /// Plain words for the bubble: no speaker labels, quotes, actions or
    /// line breaks, and no longer than `most` letters (cut at a word).
    static func clean(_ raw: String, name: String, most: Int) -> String? {
        var text = raw.replacingOccurrences(of: "\n", with: " ")
        // Actions in asterisks.
        while let a = text.firstIndex(of: "*"), let b = text[text.index(after: a)...].firstIndex(of: "*") {
            text.removeSubrange(a...b)
        }
        text = text.trimmingCharacters(in: .whitespaces)
        for label in ["You:", "Thought:", "\(name):", "Me:"] where text.lowercased().hasPrefix(label.lowercased()) {
            text = String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
        }
        let quotes = CharacterSet(charactersIn: "\"\u{201C}\u{201D}'\u{2018}\u{2019}`")
        text = text.trimmingCharacters(in: quotes.union(.whitespaces))
        text = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        if text.count > most {
            // At the end of a sentence if one ends late enough, else a word.
            let cut = String(text.prefix(most))
            if let end = cut.lastIndex(where: { ".!?".contains($0) }), cut.distance(from: cut.startIndex, to: end) > most / 2 {
                text = String(cut[...end])
            } else if let space = cut.lastIndex(of: " ") {
                text = String(cut[..<space]) + "…"
            } else {
                text = cut + "…"
            }
        }
        return text
    }
}
