import Foundation

/// In-memory ring buffer of engine-decision lines, exportable from Settings
/// so a user can hand us exactly what happened without a developer attached.
actor LogBuffer {
    static let shared = LogBuffer()

    private var lines: [String] = []
    private let maxLines = 400
    private let started = Date()

    func record(_ message: String) {
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        lines.append("[t+\(elapsed)ms] \(message)")
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    func dump() -> String {
        lines.joined(separator: "\n")
    }
}

/// Convenience for call sites that are not already in an actor context.
func logEngine(_ message: String) {
    let msg = message
    Task { await LogBuffer.shared.record(msg) }
}
