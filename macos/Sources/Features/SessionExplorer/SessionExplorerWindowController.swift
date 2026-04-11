import AppKit
import SwiftUI

@MainActor
final class SessionExplorerWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let assertController: SessionAssertController

    convenience init() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            preconditionFailure("Session Explorer requires the Ghostty app delegate.")
        }

        self.init(assertController: SessionAssertController(ghostty: appDelegate.ghostty))
    }

    init(assertController: SessionAssertController) {
        self.assertController = assertController

        let window = SessionExplorerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Session Explorer"
        window.center()
        window.tabbingMode = .disallowed

        window.contentView = NSHostingView(
            rootView: SessionExplorerView(
                refreshLiveState: {
                    explorerDebugLog("refreshLiveState requested")
                    let json = await MainActor.run {
                        SurfaceListSnapshotter.snapshot()
                    }

                    do {
                        let snapshot = try ExplorerSnapshot.fromSurfaceListSnapshot(json)
                        explorerDebugLog(
                            "refreshLiveState succeeded: windows=\(snapshot.windows.count)"
                        )
                        return snapshot
                    } catch {
                        explorerDebugLog("refreshLiveState failed: error=\(error)")
                        return nil
                    }
                },
                computeDiff: { session, liveState in
                    guard let live = liveState else {
                        explorerDebugLog(
                            "computeDiff skipped: session_id=\(session.id) live_state=nil"
                        )
                        return nil
                    }

                    let diff = SessionDiff.diff(session: session.snapshot, live: live)
                    explorerDebugLog(
                        "computeDiff completed: session_id=\(session.id) windows=\(diff.windows.count) missing=\(diff.missingCount) partial=\(diff.partialCount) match=\(diff.matchCount)"
                    )
                    return diff
                },
                onSnapshotCurrent: { [weak assertController] in
                    explorerDebugLog("onSnapshotCurrent invoked")
                    assertController?.snapshotCurrent()
                },
                onAssertAll: { [weak assertController] session in
                    explorerDebugLog(
                        "onAssertAll closure fired: session_id=\(session.id) windows=\(session.snapshot.windows.count)"
                    )
                    guard let ac = assertController else {
                        explorerDebugLog("onAssertAll aborted: assertController released")
                        return
                    }
                    Task { @MainActor in await ac.assertAll(session.snapshot) }
                },
                onAssertWindow: { [weak assertController] session, windowDiff in
                    explorerDebugLog(
                        "onAssertWindow closure fired: session_id=\(session.id) diff_id=\(windowDiff.id) title=\(windowDiff.title) status=\(String(describing: windowDiff.status))"
                    )
                    guard let ac = assertController else {
                        explorerDebugLog("onAssertWindow aborted: assertController released")
                        return
                    }
                    if let window = session.snapshot.windows.first(where: { $0.id == windowDiff.id }) {
                        explorerDebugLog(
                            "onAssertWindow matched snapshot window: window_id=\(window.id) tabs=\(window.tabs.count)"
                        )
                        Task { @MainActor in await ac.assertWindow(window) }
                    } else {
                        explorerDebugLog(
                            "onAssertWindow could not match diff to snapshot window: diff_id=\(windowDiff.id)"
                        )
                    }
                }
            )
        )

        super.init(window: window)

        window.delegate = self
        window.isReleasedWhenClosed = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    @objc func performClose(_ sender: Any?) {
        window?.close()
    }
}

/// Custom window that intercepts Cmd+W before Ghostty's local event monitor
/// can consume it for terminal close_tab. Non-terminal windows need standard
/// AppKit close behavior.
final class SessionExplorerWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.shift),
           !event.modifierFlags.contains(.option),
           event.charactersIgnoringModifiers == "w" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
