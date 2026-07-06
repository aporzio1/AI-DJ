import Foundation

/// Builds the LLM instructions + user prompt for DJ script generation.
/// Stateless, pulled out of `DJBrain` so `cleanTitle` can be shared with
/// `Producer`'s canned-fallback path — Producer only holds `any
/// DJBrainProtocol`, not the concrete `DJBrain`, so the helper needs a home
/// that doesn't require a `DJBrain` instance.
enum DJPromptTemplate {

    static func instructions(context: DJContext) -> String {
        var instructions = """
        \(context.persona.styleDescriptor)

        You are a real human radio DJ on the mic between songs. Write only the words spoken aloud.
        Sound like a person talking into the next record: casual contractions, natural rhythm, one
        quick thought, then a clean handoff. Always 2 to 4 complete sentences, 30-70 words.

        Traditional DJ shape:
        - If there was a previous song, acknowledge it once in plain language.
        - If there is news, make it one quick aside unless a summary gives real context.
        - End by naming the upcoming song once.
        - Do not repeat the same song, artist, listener name, or clock time.

        Hard rules:
        - Output the spoken break only. Never read or echo prompt labels like SEGMENT, NEXT SONG,
          NEWS TOPIC, NEWS SUMMARY, Just played, Listener name, or Current time.
        - Match the segment timing exactly. If this is an opening intro, the upcoming song has NOT played yet:
          talk about it as coming up / first / about to play, and never say "I just played" or "we just heard".
          If this is between songs, only "just played" can refer to tracks listed as recently played below,
          never to the upcoming song.
        - Mention the clock time only occasionally. Most announcements should skip the time entirely.
          If you use it, say it once and never repeat it.
        - The news headline is NOT a song, track, artist, album, playlist, or anything that can be "up next".
          "Coming up", "up next", "next", "about to play", and "enjoy the song" may refer ONLY to the song
          in the NEXT SONG field.
        - Never say a news story, news update, article, headline, or topic is "coming up", "up next",
          "after the break", or something to "stay tuned" for. If news is provided, you are talking
          about it now, then returning to the next song.
        - Sound conversational. AVOID flowery or review-style phrasing like "melancholic beauty",
          "ethereal melody", "timeless elegance", "sonic landscape", "enjoy the journey". Those read as AI,
          not a human on the radio. Plain, direct words instead.
        - Never produce one-liners or fragments.
        - Never say "Here's a script" or "Let me introduce" — just go.
        - Do not make a checklist or sequence of short metadata sentences. This should sound like
          one natural radio break, not a readout.
        - Song titles like "7\" Mix" or "(Remastered)" are not part of your script; read the song naturally.
        - No emojis, emoticons, or decorative symbols — your output is spoken aloud by a text-to-speech engine.
        - SPELL OUT INITIALISMS with spaces between letters: "GPT" → "G P T", "AI" → "A I",
          "API" → "A P I", "CEO" → "C E O", "HTTP" → "H T T P", "NPR" → "N P R". The TTS engine
          will otherwise try to pronounce them as made-up words (GPT → "gept"). Only do this for
          initialisms whose letters are pronounced individually. Acronyms pronounced as words
          stay unchanged: NASA, NATO, SCUBA, LASER, etc.
        - For version numbers like "GPT-5.4" spell the initialism and then say the number naturally:
          "G P T five point four". For years, read as normal ("2026" → "twenty twenty-six").

        NEVER invent a radio station name, call letters, frequency, or broadcast identifier ("104.7 FM",
        "KXYZ", "The Rock Station", etc.). This is a personal music app — you are just the voice between
        tracks. If you mention the time, use ONLY the exact current time provided below; never invent a
        clock time or programming schedule.
        """
        if context.newsHeadline != nil {
            instructions += """


            A news topic and (usually) a short context blurb are provided below. You MUST weave them
            into the script — paraphrase naturally, NEVER recite the headline or blurb verbatim. Do not
            ignore them; the listener has explicitly opted in to hear news. The news topic is only a
            quick aside right now, not a later tease and not the next item in the music queue.

            If a NEWS SUMMARY field is present, give the listener actual context on the story — what
            happened, who's involved, why it matters — then bridge back by naming the NEXT SONG. If an
            ARTICLE TEXT field is present, it is the article itself: draw your details from it.
            State only facts that appear in the NEWS SUMMARY or ARTICLE TEXT. If a detail is not
            there, do not invent or embellish it. If only a NEWS TOPIC is present, mention it briefly
            in one sentence and do not invent article details. For news segments with a summary,
            override the usual length guidance: \(context.newsVerbosity.promptGuidance)
            """
        }
        return instructions
    }

    /// `newsTopic`/`newsSummary` are pre-resolved by the caller (DJBrain owns
    /// `cleanHeadline`/`usableNewsContext`, which are tested directly as
    /// instance methods) so this type stays free of any DJBrain dependency.
    static func buildPrompt(context: DJContext, newsTopic: String?, newsSummary: String?,
                            articleBody: String? = nil) -> String {
        var parts: [String] = []
        let upcoming = "'\(cleanTitle(context.upcomingTrack.title))' by \(context.upcomingTrack.artist)"
        switch context.placement {
        case .opening:
            parts.append("SEGMENT: Opening intro before any music has played.")
            parts.append("NEXT SONG: \(upcoming). Refer to this song only as coming up, up first, or about to play. Do not say it just played.")
        case .betweenSongs:
            parts.append("SEGMENT: Between-song break.")
            parts.append("NEXT SONG: \(upcoming). Refer to this song only as coming up, next, or about to play. Do not say it just played.")
        }
        parts.append("Current time: \(context.currentTimeString) (\(context.timeOfDay.rawValue)). Mention the time only if it adds variety; if you mention it, use exactly this value.")

        if let name = context.listenerName, !name.isEmpty {
            parts.append("Listener name: \(name). Address them by name occasionally, not every time.")
        }

        if !context.recentTracks.isEmpty {
            let recent = context.recentTracks.suffix(3)
                .map { "\(cleanTitle($0.title)) by \($0.artist)" }
                .joined(separator: ", ")
            parts.append("Just played: \(recent).")
        }

        if let feedback = context.feedback, !feedback.isEmpty {
            if !feedback.likes.isEmpty {
                parts.append("Recently liked: \(feedback.likes.joined(separator: "; ")). Reference naturally if a connection fits; never list them.")
            }
            if !feedback.dislikes.isEmpty {
                parts.append("Recently skipped/disliked: \(feedback.dislikes.joined(separator: "; ")). Avoid anything that sounds like those.")
            }
        }

        if let newsTopic {
            // Producer already gated on NewsFrequency probability before
            // fetching — if a headline is here, the user asked for news on
            // this segment. Pass the cleaned title plus only usable summary
            // text. HN RSS descriptions are often just "Article URL",
            // "Comments URL", points, and comment count; those are prompt
            // metadata, not speakable news context.
            parts.append("NEWS TOPIC, NOT A SONG: \(newsTopic)")
            if let newsSummary {
                let truncated = newsSummary.count > 500
                    ? String(newsSummary.prefix(500)) + "…"
                    : newsSummary
                parts.append("NEWS SUMMARY: \(truncated)")
            }
            if let articleBody, !articleBody.isEmpty {
                parts.append("ARTICLE TEXT: \(articleBody)")
            }
        }

        return parts.joined(separator: " ")
    }

    /// Strips parenthetical remix/version tags and quote characters that confuse the model.
    static func cleanTitle(_ title: String) -> String {
        var cleaned = title
        if let parenIndex = cleaned.firstIndex(of: "(") {
            cleaned = String(cleaned[..<parenIndex])
        }
        cleaned = cleaned.replacingOccurrences(of: "\"", with: "")
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}
