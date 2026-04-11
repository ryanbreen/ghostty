import Foundation
import Combine

final class SessionStore: ObservableObject {
    @Published var sessions: [StoredSession] = []

    struct StoredSession: Identifiable {
        let id: String
        let path: String
        let date: Date
        let snapshot: ExplorerSnapshot
        let isLatest: Bool

        var windowCount: Int { snapshot.windows.count }
        var tabCount: Int { snapshot.windows.flatMap(\.tabs).count }
    }

    private var changeObserver: NSObjectProtocol?

    init() {
        // Reload whenever anyone (manual Save Session, auto-save timer, or the
        // Session Explorer's Snapshot Current button) writes a snapshot to disk.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .ghosttySessionsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadSessions()
        }
    }

    deinit {
        if let obs = changeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func loadSessions() {
        let fileManager = FileManager.default

        guard let urls = try? fileManager.contentsOfDirectory(
            at: Self.sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            sessions = []
            return
        }

        let loadedSessions = urls.compactMap { url -> StoredSession? in
            guard url.pathExtension == "json" else { return nil }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            let isRegularFile = values?.isRegularFile ?? false
            let isSymbolicLink = values?.isSymbolicLink ?? false
            guard isRegularFile || isSymbolicLink else { return nil }

            let resolvedURL = url.resolvingSymlinksInPath()
            guard
                let data = try? Data(contentsOf: resolvedURL),
                let snapshot = try? JSONDecoder().decode(ExplorerSnapshot.self, from: data)
            else {
                return nil
            }

            let date = Self.timestamp(from: url) ?? Self.timestamp(from: resolvedURL) ?? Self.modificationDate(for: resolvedURL) ?? .distantPast

            return StoredSession(
                id: url.lastPathComponent,
                path: url.path,
                date: date,
                snapshot: snapshot,
                isLatest: url.lastPathComponent == "latest.json" || isSymbolicLink
            )
        }

        sessions = loadedSessions.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            if lhs.isLatest != rhs.isLatest {
                return lhs.isLatest && !rhs.isLatest
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    func saveSnapshot(_ json: String, prefix: String) {
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(
                at: Self.sessionsDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let timestamp = Self.fileTimestampFormatter.string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let safePrefix = prefix.isEmpty ? "snapshot" : prefix
            let fileURL = Self.sessionsDirectory.appendingPathComponent("\(safePrefix)-\(timestamp).json")

            guard let data = json.data(using: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }

            try data.write(to: fileURL, options: [.atomic])
            loadSessions()
        } catch {
            assertionFailure("Failed to save session snapshot: \(error)")
        }
    }
}

extension SessionStore {
    static let sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config")
        .appendingPathComponent("ghostty")
        .appendingPathComponent("sessions")

    static let filenameTimestampRegex = try! NSRegularExpression(
        pattern: #"(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}(?:\.\d+)?Z)"#
    )

    static let parsedTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let parsedTimestampFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let fileTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func timestamp(from url: URL) -> Date? {
        let filename = url.lastPathComponent
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = filenameTimestampRegex.firstMatch(in: filename, range: range),
              let matchRange = Range(match.range(at: 1), in: filename) else {
            return nil
        }

        let timestamp = String(filename[matchRange])
        let isoTimestamp = timestamp.replacingOccurrences(
            of: #"T(\d{2})-(\d{2})-(\d{2})(\.\d+)?Z"#,
            with: "T$1:$2:$3$4Z",
            options: .regularExpression
        )

        return parsedTimestampFormatter.date(from: isoTimestamp)
            ?? parsedTimestampFormatterNoFraction.date(from: isoTimestamp)
    }

    static func modificationDate(for url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
