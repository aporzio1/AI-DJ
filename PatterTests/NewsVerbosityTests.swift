// PatterTests/NewsVerbosityTests.swift
import Testing
import Foundation
@testable import Patter

@Suite("NewsVerbosity")
struct NewsVerbosityTests {

    @Test func defaultIsStandard() {
        #expect(NewsVerbosity.default == .standard)
    }

    @Test func onlyUpperLevelsFetchArticles() {
        #expect(!NewsVerbosity.brief.needsArticleFetch)
        #expect(!NewsVerbosity.standard.needsArticleFetch)
        #expect(NewsVerbosity.detailed.needsArticleFetch)
        #expect(NewsVerbosity.deepDive.needsArticleFetch)
    }

    @Test func articleCapsMatchSpec() {
        #expect(NewsVerbosity.brief.articleBodyCharCap == nil)
        #expect(NewsVerbosity.standard.articleBodyCharCap == nil)
        #expect(NewsVerbosity.detailed.articleBodyCharCap == 1500)
        #expect(NewsVerbosity.deepDive.articleBodyCharCap == 3500)
    }

    @Test func scriptCapsWidenWithLevel() {
        #expect(NewsVerbosity.brief.scriptCharCap == 500)
        #expect(NewsVerbosity.standard.scriptCharCap == 500)
        #expect(NewsVerbosity.detailed.scriptCharCap == 1200)
        #expect(NewsVerbosity.deepDive.scriptCharCap == 2200)
    }

    @Test func rawValuesRoundTripForPersistence() {
        for level in NewsVerbosity.allCases {
            #expect(NewsVerbosity(rawValue: level.rawValue) == level)
        }
    }
}
