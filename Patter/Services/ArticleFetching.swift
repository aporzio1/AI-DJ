// Patter/Services/ArticleFetching.swift
import Foundation

/// Downloads an article URL and returns readable body text, or nil on any
/// failure. Callers treat nil as "fall back to the RSS summary" — this
/// service never throws into the DJ pipeline.
protocol ArticleFetching: Sendable {
    func body(for url: URL, maxChars: Int) async -> String?
}
