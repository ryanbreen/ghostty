import AppKit
import Foundation
import GhosttyKit

private let explorerDebugLogPath = "/tmp/ghostty-explorer-debug.log"

func explorerDebugLog(_ message: String) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let line = "[explorer] \(formatter.string(from: Date())) \(message)\n"
    let path = explorerDebugLogPath
    let fm = FileManager.default

    if !fm.fileExists(atPath: path) {
        fm.createFile(atPath: path, contents: nil)
    }

    guard let data = line.data(using: .utf8),
          let handle = FileHandle(forWritingAtPath: path) else {
        NSLog("[SessionExplorer] failed to open debug log at \(path)")
        return
    }

    handle.seekToEndOfFile()
    handle.write(data)
    handle.closeFile()
}

@MainActor
final class SessionAssertController {
    private let ghostty: Ghostty.App
    private var hasCapturedPreAssertSnapshot = false

    init(ghostty: Ghostty.App) {
        self.ghostty = ghostty
    }

    func assertWindow(_ window: ExplorerWindow) async {
        explorerDebugLog(
            "assertWindow called: window_id=\(window.id) title=\(window.displayTitle) tabs=\(window.tabs.count)"
        )
        capturePreAssertSnapshotIfNeeded()

        do {
            let sessionPath = try writeTemporarySessionDocument(for: window)
            explorerDebugLog("assertWindow wrote temporary session file: \(sessionPath)")
            defer {
                do {
                    try FileManager.default.removeItem(atPath: sessionPath)
                    explorerDebugLog("assertWindow removed temporary session file: \(sessionPath)")
                } catch {
                    explorerDebugLog(
                        "assertWindow failed to remove temporary session file: \(sessionPath) error=\(error)"
                    )
                }
            }

            let createdWindowMap = try SessionRestorer.restore(from: sessionPath, ghostty: ghostty)
            explorerDebugLog(
                "assertWindow restore scheduled successfully: window_id=\(window.id) created_window_map=\(createdWindowMap)"
            )
        } catch {
            explorerDebugLog("assertWindow failed: window_id=\(window.id) error=\(error)")
            Ghostty.logger.error("session explorer assertWindow failed: \(String(describing: error))")
        }
    }

    func assertAll(_ snapshot: ExplorerSnapshot) async {
        explorerDebugLog("assertAll called: windows=\(snapshot.windows.count)")
        capturePreAssertSnapshotIfNeeded()
        for (index, window) in snapshot.windows.enumerated() {
            explorerDebugLog(
                "assertAll asserting window \(index + 1)/\(snapshot.windows.count): window_id=\(window.id) title=\(window.displayTitle)"
            )
            await assertWindow(window)
        }
        explorerDebugLog("assertAll finished")
    }

    @discardableResult
    func snapshotCurrent() -> String? {
        let json = SurfaceListSnapshotter.snapshot()
        let dir = SessionStore.sessionsDirectory
        let fm = FileManager.default

        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "pre-assert-\(stamp).json"
        let path = dir.appendingPathComponent(filename).path

        do {
            try json.write(toFile: path, atomically: true, encoding: .utf8)
            explorerDebugLog("snapshotCurrent saved pre-assert snapshot: \(path)")
            return path
        } catch {
            explorerDebugLog("snapshotCurrent failed to save pre-assert snapshot: error=\(error)")
            return nil
        }
    }

    private func capturePreAssertSnapshotIfNeeded() {
        guard !hasCapturedPreAssertSnapshot else {
            explorerDebugLog("capturePreAssertSnapshotIfNeeded skipped: snapshot already captured")
            return
        }
        hasCapturedPreAssertSnapshot = true
        explorerDebugLog("capturePreAssertSnapshotIfNeeded capturing snapshot")
        snapshotCurrent()
    }

    private func writeTemporarySessionDocument(for window: ExplorerWindow) throws -> String {
        let document = try serializedSessionDocument(for: window)
        let path = "/tmp/ghostty-explorer-assert-\(UUID().uuidString).json"
        try document.write(to: URL(fileURLWithPath: path), options: [.atomic])
        return path
    }

    private func serializedSessionDocument(for window: ExplorerWindow) throws -> Data {
        let windowRecord = try makeWindowRecord(window)
        let document: [String: Any] = [
            "version": SessionDocument.currentVersion,
            "windows": [windowRecord],
        ]

        let data = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        )
        explorerDebugLog(
            "serializedSessionDocument built JSON payload: window_id=\(window.id) bytes=\(data.count)"
        )
        return data
    }

    private func makeWindowRecord(_ window: ExplorerWindow) throws -> [String: Any] {
        let tabs = try window.tabs.enumerated().map { index, tab in
            try makeTabRecord(tab, windowID: window.id, tabIndex: index)
        }

        var record: [String: Any] = [
            "id": window.id,
            "tabs": tabs,
        ]

        if let title = nonEmpty(window.title) {
            record["title"] = title
        }

        if let workspace = window.workspace {
            record["workspace"] = workspace
        }

        explorerDebugLog(
            "makeWindowRecord encoded window: window_id=\(window.id) title=\(window.title ?? "<nil>") workspace=\(String(describing: window.workspace)) tabs=\(tabs.count)"
        )
        return record
    }

    private func makeTabRecord(_ tab: ExplorerTab, windowID: String, tabIndex: Int) throws -> [String: Any] {
        var record: [String: Any] = [
            "surfaceTree": [
                "root": try encodeSurfaceNode(tab.surfaceTree.root),
            ],
        ]

        if let title = nonEmpty(tab.title) {
            record["title"] = title
        }

        explorerDebugLog(
            "makeTabRecord encoded tab: window_id=\(windowID) tab_index=\(tabIndex) title=\(tab.title ?? "<nil>") panes=\(tab.paneCount)"
        )
        return record
    }

    private func encodeSurfaceNode(_ node: ExplorerSurfaceNode) throws -> [String: Any] {
        switch node {
        case .view(let view):
            return ["view": encodeSurfaceView(view)]
        case .split(let split):
            return [
                "split": [
                    "direction": split.direction,
                    "ratio": split.ratio,
                    "left": try encodeSurfaceNode(split.left),
                    "right": try encodeSurfaceNode(split.right),
                ],
            ]
        }
    }

    private func encodeSurfaceView(_ view: ExplorerSurfaceView) -> [String: Any] {
        var record: [String: Any] = [:]

        if let pwd = nonEmpty(view.pwd) {
            record["pwd"] = pwd
        }

        if let title = nonEmpty(view.title) {
            record["title"] = title
        }

        return record
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
