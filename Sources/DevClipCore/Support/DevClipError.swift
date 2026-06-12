import Foundation

/// Structured errors shared by Phase 0 placeholders and future services.
public enum DevClipError: Error, Equatable, Sendable {
    case notImplemented(feature: String, phase: String)
    case invalidInput(reason: String)
    case cancelled
    case timedOut(seconds: TimeInterval)
}

extension DevClipError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .notImplemented(feature, phase):
            "\(feature) is reserved for \(phase) and is not implemented yet."
        case let .invalidInput(reason):
            reason
        case .cancelled:
            "The operation was cancelled."
        case let .timedOut(seconds):
            "The operation timed out after \(seconds) seconds."
        }
    }
}
