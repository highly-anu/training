import Combine
import Foundation

/// Simple in-process log ring-buffer. Thread-safe via @MainActor.
@MainActor
final class AppLogger: ObservableObject {
    static let shared = AppLogger()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let message: String
    }

    @Published var entries: [Entry] = []
    private let maxEntries = 100

    private init() {}

    func log(_ message: String) {
        let entry = Entry(date: Date(), message: message)
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst() }
        // Mirror to Xcode console
        print("[AppLogger] \(message)")
    }

    /// Convenience: call from non-isolated contexts.
    nonisolated func logFromBackground(_ message: String) {
        Task { @MainActor in AppLogger.shared.log(message) }
    }
}
