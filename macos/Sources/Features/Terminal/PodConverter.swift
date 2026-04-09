import AppKit
import GhosttyKit

/// Converts the focused tab into a full pod layout: a 3-column, 4-pane split
/// where every surface lands in the same working directory.
///
/// Layout (matches Hive's standard pod):
///   left  |  middle  |  right-top
///                     right-bottom
///
/// The conversion adds a new tab with the pod layout, then closes the
/// original single-pane tab so the user ends up with the expanded view.

@MainActor
enum PodConverter {

    /// Expand the focused tab of `controller` into the standard pod layout.
    /// The directory is taken from the focused surface's pwd.
    static func convertFocusedToPod(controller: BaseTerminalController, ghostty: Ghostty.App) {
        guard let pwd = controller.focusedSurface?.pwd, !pwd.isEmpty else {
            Ghostty.logger.warning("pod convert: no pwd available from focused surface")
            return
        }
        convert(directory: pwd, controller: controller, ghostty: ghostty)
    }

    /// Expand into a pod layout using an explicit directory.
    static func convert(directory: String, controller: BaseTerminalController, ghostty: Ghostty.App) {
        let dir = (directory as NSString).expandingTildeInPath

        guard let tree = buildPodTree(directory: dir) else {
            Ghostty.logger.error("pod convert: failed to build split tree for '\(dir)'")
            return
        }

        let tabController = TerminalController(ghostty, withSurfaceTree: tree)
        let tabTitle = URL(fileURLWithPath: dir).lastPathComponent
        tabController.titleOverride = tabTitle

        guard let existingWindow = controller.window,
              let tabWindow = tabController.window else { return }

        existingWindow.addTabbedWindowSafely(tabWindow, ordered: .above)
        tabWindow.makeKeyAndOrderFront(nil)

        // Close the original tab (single-pane) if it had only one surface.
        let originalLeafCount = leafCount(controller.surfaceTree.root)
        if originalLeafCount <= 1 {
            existingWindow.close()
        }

        Ghostty.logger.info("pod convert: created pod tab '\(tabTitle)' at '\(dir)'")
    }

    // MARK: - Build the Pod Split Tree

    /// Build a 4-pane pod layout as a SplitTree decoded from JSON.
    /// Using JSON as the construction path lets us reuse the exact same
    /// surface initialisation path as session restore.
    ///
    ///   left (0.33) | middle + right (0.67)
    ///                 middle (0.5) | right-top + right-bottom (0.5)
    ///                               right-top (0.5)
    ///                               right-bottom
    private static func buildPodTree(directory: String) -> SplitTree<Ghostty.SurfaceView>? {
        func surface(_ dir: String) -> [String: Any] {
            let shellEscaped = "'" + dir.replacingOccurrences(of: "'", with: "'\\''") + "'"
            return [
                "pwd": dir,
                "initialInput": "cd -- \(shellEscaped)\n"
            ]
        }

        let s = surface(directory)

        let rightColumn: [String: Any] = [
            "split": [
                "direction": ["vertical": [:]],
                "ratio": 0.5,
                "left": ["view": s],
                "right": ["view": s]
            ]
        ]

        let middleAndRight: [String: Any] = [
            "split": [
                "direction": ["horizontal": [:]],
                "ratio": 0.5,
                "left": ["view": s],
                "right": rightColumn
            ]
        ]

        let root: [String: Any] = [
            "split": [
                "direction": ["horizontal": [:]],
                "ratio": 0.33,
                "left": ["view": s],
                "right": middleAndRight
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: ["root": root]),
              let treeWrapper = try? JSONDecoder().decode(SessionSurfaceTree.self, from: data) else {
            return nil
        }

        return SplitTree<Ghostty.SurfaceView>(root: treeWrapper.root, zoomed: nil)
    }

    // MARK: - Helpers

    private static func leafCount(_ node: SplitTree<Ghostty.SurfaceView>.Node?) -> Int {
        guard let node else { return 0 }
        switch node {
        case .leaf: return 1
        case .split(let s): return leafCount(s.left) + leafCount(s.right)
        }
    }
}
