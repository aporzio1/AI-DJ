import Foundation
import os

/// Central logger registry. Filter by subsystem `com.andrewporzio.aidj` in Console.app
/// or Xcode Debug → Logging, and further by category below.
enum Log {
    private static let subsystem = "com.andrewporzio.aidj"

    static let app         = Logger(subsystem: subsystem, category: "App")
    static let onboarding  = Logger(subsystem: subsystem, category: "Onboarding")
    static let coordinator = Logger(subsystem: subsystem, category: "Coordinator")
    static let producer    = Logger(subsystem: subsystem, category: "Producer")
    static let brain       = Logger(subsystem: subsystem, category: "DJBrain")
    static let voice       = Logger(subsystem: subsystem, category: "DJVoice")
    static let audio       = Logger(subsystem: subsystem, category: "AudioGraph")
    static let musicKit    = Logger(subsystem: subsystem, category: "MusicKit")
    static let spotify     = Logger(subsystem: subsystem, category: "Spotify")
}
