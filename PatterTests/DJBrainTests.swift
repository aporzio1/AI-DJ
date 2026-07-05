import Testing
import Foundation
@testable import Patter

@Suite("DJBrain")
struct DJBrainTests {

    @Test func newsHeadlineCannotBecomeNextSong() {
        let brain = DJBrain()
        let context = DJContext(
            placement: .betweenSongs,
            persona: .default,
            upcomingTrack: Track.stub(title: "No Quiero Amarte"),
            recentTracks: [Track.stub(title: "Te Bote")],
            timeOfDay: .evening,
            currentTimeString: "8:35 PM",
            newsHeadline: NewsHeadline(
                id: UUID(),
                title: "Fast Fourier Transforms: for fun and profit (1966)",
                source: "hnrss.org",
                url: URL(string: "https://example.com/story")!,
                publishedAt: Date(timeIntervalSince1970: 0),
                summary: "Article URL: https://example.com/story"
            ),
            listenerName: "Andrew",
            feedback: nil
        )
        let badScript = """
        Andrew, it's 8:35 PM. Fast Fourier Transforms: for fun and profit (1966) is coming up next. \
        The article talks about mathematical techniques. Enjoy the song, Andrew!
        """

        let guarded = brain.enforceSongNewsBoundary(badScript, context: context)

        #expect(!guarded.contains("Fast Fourier Transforms: for fun and profit (1966) is coming up next"))
        #expect(guarded.contains("Up next, No Quiero Amarte by Artist."))
    }

    @Test func genericNewsTeaseCannotUseComingUpLanguage() {
        let brain = DJBrain()
        let context = DJContext(
            placement: .opening,
            persona: .default,
            upcomingTrack: Track.stub(title: "X"),
            recentTracks: [],
            timeOfDay: .evening,
            currentTimeString: "8:43 PM",
            newsHeadline: NewsHeadline(
                id: UUID(),
                title: "New CEO Steve O'Donnell vows to unite NASCAR and return the fun",
                source: "feeds.npr.org",
                url: URL(string: "https://example.com/story")!,
                publishedAt: Date(timeIntervalSince1970: 0),
                summary: "Steve O'Donnell was introduced as chief executive officer."
            ),
            listenerName: "Andrew",
            feedback: nil
        )
        let badScript = """
        Andrew, welcome to the show at 8:43 PM. We've got a big news update coming up, but first, \
        we're kicking off with some high-energy tunes. X by Artist is about to play.
        """

        let guarded = brain.enforceSongNewsBoundary(badScript, context: context)

        #expect(!guarded.contains("news update coming up"))
        #expect(guarded.contains("X by Artist"))
    }

    @Test func promptMetadataLeakageIsRemovedBeforeSpeech() {
        let brain = DJBrain()
        let leakedScript = """
        Andrew, we're about to kick it up a notch with Te Boté by Nio Garcia, Casper Magico, and Darell. \
        Just played: X by Nicky Jam & J Balvin. NEWS TOPIC, NOT A SONG: Usage limits for each of the Claude plans \
        NEWS CONTEXT: Article URL: https://xcancel.com/nrehiew_/status/2048009931757097079 Comments URL: https://news.ycombinator.com/item?id=47906192
        """

        let sanitized = brain.sanitizePromptLeakage(leakedScript)

        #expect(sanitized.contains("Te Boté"))
        #expect(!sanitized.contains("Just played:"))
        #expect(!sanitized.contains("NEWS TOPIC"))
        #expect(!sanitized.contains("NEWS CONTEXT"))
        #expect(!sanitized.contains("https://"))
        #expect(!sanitized.contains("xcancel"))
        #expect(!sanitized.contains("ycombinator"))
    }

    @Test func accentDifferencesDoNotCreateDuplicateUpcomingCallout() {
        let brain = DJBrain()
        let context = DJContext(
            placement: .betweenSongs,
            persona: .default,
            upcomingTrack: Track(
                id: "next",
                title: "Te Boté",
                artist: "Nio García, Casper Mágico & Darell",
                album: "Album",
                artworkURL: nil,
                duration: 180,
                providerID: .appleMusic
            ),
            recentTracks: [
                Track(
                    id: "recent",
                    title: "X",
                    artist: "Nicky Jam & J Balvin",
                    album: "Album",
                    artworkURL: nil,
                    duration: 180,
                    providerID: .appleMusic
                )
            ],
            timeOfDay: .evening,
            currentTimeString: "9:09 PM",
            newsHeadline: NewsHeadline(
                id: UUID(),
                title: "Multiple AI Models in One Platform",
                source: "example.com",
                url: URL(string: "https://example.com/story")!,
                publishedAt: Date(timeIntervalSince1970: 0),
                summary: ""
            ),
            listenerName: "Andrew",
            feedback: nil
        )
        let script = """
        Hey Andrew, 9:09 PM. Just played X by Nicky Jam & J Balvin. \
        About to play Te Bote by Nio Garcia, Casper Magico & Darell.
        """

        let guarded = brain.enforceSongNewsBoundary(script, context: context)

        #expect(!guarded.contains("Up next, Te Boté by Nio García, Casper Mágico & Darell."))
    }

    @Test func urlOnlyNewsSummaryIsNotUsableContext() {
        let brain = DJBrain()
        let summary = """
        Article URL: https://xcancel.com/nrehiew_/status/2048009931757097079 \
        Comments URL: https://news.ycombinator.com/item?id=47906192 Points: 1 # Comments: 0
        """

        #expect(brain.usableNewsContext(from: summary) == nil)
    }

    @Test func articleSummaryKeepsHumanReadableContext() {
        let brain = DJBrain()
        let summary = """
        <p>Steve O'Donnell was introduced as NASCAR's chief executive officer at Talladega and promised \
        changes aimed at making the racing series feel more connected to its roots.</p>
        """

        let context = brain.usableNewsContext(from: summary)

        #expect(context?.contains("Steve O'Donnell") == true)
        #expect(context?.contains("<p>") == false)
    }

    @Test func splitSentencesPreservesOriginalTerminators() {
        let brain = DJBrain()
        let mixed = "Wow! Up next, Paranoid Android. Are you ready?"

        let sentences = brain.splitSentences(mixed)

        #expect(sentences == ["Wow!", "Up next, Paranoid Android.", "Are you ready?"])
    }

    @Test func splitSentencesAppendsPeriodToUnterminatedTrailing() {
        let brain = DJBrain()
        let trailing = "First sentence. No terminator here"

        let sentences = brain.splitSentences(trailing)

        #expect(sentences == ["First sentence.", "No terminator here."])
    }

    // MARK: - DJPromptTemplate.cleanTitle

    @Test func cleanTitleStripsParentheticalSuffix() {
        #expect(DJPromptTemplate.cleanTitle("Paranoid Android (Remastered)") == "Paranoid Android")
    }

    @Test func cleanTitleStripsQuoteCharacters() {
        #expect(DJPromptTemplate.cleanTitle("7\" Mix") == "7 Mix")
    }

    @Test func cleanTitleLeavesPlainTitleUntouched() {
        #expect(DJPromptTemplate.cleanTitle("Te Boté") == "Te Boté")
    }

    // MARK: - DJPromptTemplate.buildPrompt

    private func makeContext(
        placement: DJContext.Placement = .betweenSongs,
        recentTracks: [Track] = [],
        listenerName: String? = nil,
        feedback: FeedbackSummary? = nil,
        newsHeadline: NewsHeadline? = nil
    ) -> DJContext {
        DJContext(
            placement: placement,
            persona: .default,
            upcomingTrack: Track.stub(id: "next", title: "Next Song"),
            recentTracks: recentTracks,
            timeOfDay: .evening,
            currentTimeString: "8:00 PM",
            newsHeadline: newsHeadline,
            listenerName: listenerName,
            feedback: feedback
        )
    }

    @Test func buildPromptOpeningFramesUpcomingTrackAsNotYetPlayed() {
        let context = makeContext(placement: .opening)
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: nil, newsSummary: nil)

        #expect(prompt.contains("Opening intro before any music has played"))
        #expect(prompt.contains("coming up, up first, or about to play"))
        #expect(!prompt.contains("Just played:"))
    }

    @Test func buildPromptBetweenSongsFramesUpcomingTrackAsNext() {
        let context = makeContext(placement: .betweenSongs)
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: nil, newsSummary: nil)

        #expect(prompt.contains("Between-song break"))
        #expect(prompt.contains("coming up, next, or about to play"))
    }

    @Test func buildPromptOmitsListenerNameWhenNil() {
        let context = makeContext(listenerName: nil)
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: nil, newsSummary: nil)

        #expect(!prompt.contains("Listener name:"))
    }

    @Test func buildPromptIncludesListenerNameWhenPresent() {
        let context = makeContext(listenerName: "Andrew")
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: nil, newsSummary: nil)

        #expect(prompt.contains("Listener name: Andrew"))
    }

    @Test func buildPromptOmitsRecentTracksWhenEmpty() {
        let context = makeContext(recentTracks: [])
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: nil, newsSummary: nil)

        #expect(!prompt.contains("Just played:"))
    }

    @Test func buildPromptIncludesLastThreeRecentTracksCleaned() {
        let context = makeContext(recentTracks: [
            Track.stub(id: "1", title: "One (Live)"),
            Track.stub(id: "2", title: "Two"),
            Track.stub(id: "3", title: "Three"),
            Track.stub(id: "4", title: "Four"),
        ])
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: nil, newsSummary: nil)

        #expect(prompt.contains("Just played: Two by Artist, Three by Artist, Four by Artist."))
        #expect(!prompt.contains("One"))
    }

    @Test func buildPromptOmitsFeedbackSectionsWhenNil() {
        let context = makeContext(feedback: nil)
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: nil, newsSummary: nil)

        #expect(!prompt.contains("Recently liked:"))
        #expect(!prompt.contains("Recently skipped"))
    }

    @Test func buildPromptIncludesOnlyNonEmptyFeedbackSections() {
        let context = makeContext(feedback: FeedbackSummary(likes: ["Song A by Artist A"], dislikes: []))
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: nil, newsSummary: nil)

        #expect(prompt.contains("Recently liked: Song A by Artist A"))
        #expect(!prompt.contains("Recently skipped"))
    }

    @Test func buildPromptOmitsNewsSectionWhenTopicIsNil() {
        let context = makeContext()
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: nil, newsSummary: nil)

        #expect(!prompt.contains("NEWS TOPIC"))
        #expect(!prompt.contains("NEWS SUMMARY"))
    }

    @Test func buildPromptIncludesNewsTopicWithoutSummary() {
        let context = makeContext()
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: "A big story", newsSummary: nil)

        #expect(prompt.contains("NEWS TOPIC, NOT A SONG: A big story"))
        #expect(!prompt.contains("NEWS SUMMARY"))
    }

    @Test func buildPromptIncludesNewsSummaryWhenPresent() {
        let context = makeContext()
        let prompt = DJPromptTemplate.buildPrompt(context: context, newsTopic: "A big story", newsSummary: "Context about the story.")

        #expect(prompt.contains("NEWS SUMMARY: Context about the story."))
    }

    // MARK: - DJPromptTemplate.instructions

    @Test func instructionsOmitNewsGuidanceWhenNoHeadline() {
        let context = makeContext(newsHeadline: nil)
        let instructions = DJPromptTemplate.instructions(context: context)

        #expect(!instructions.contains("A news topic"))
    }

    @Test func instructionsIncludeNewsGuidanceWhenHeadlinePresent() {
        let context = makeContext(newsHeadline: NewsHeadline(
            id: UUID(),
            title: "Some headline",
            source: "example.com",
            url: URL(string: "https://example.com")!,
            publishedAt: Date(timeIntervalSince1970: 0),
            summary: "Summary"
        ))
        let instructions = DJPromptTemplate.instructions(context: context)

        #expect(instructions.contains("A news topic"))
    }

    @Test func instructionsIncludePersonaStyleDescriptor() {
        let context = makeContext()
        let instructions = DJPromptTemplate.instructions(context: context)

        #expect(instructions.contains(DJPersona.default.styleDescriptor))
    }
}
