import AppKit
import GhosttyKit

/// Captures all currently open terminal surfaces as a flat JSON array.
@MainActor
enum SurfaceListSnapshotter {
    static func snapshot() -> String {
        let focusedSurface = (NSApp.keyWindow?.windowController as? BaseTerminalController)?.focusedSurface
        let controllers = NSApp.orderedWindows.compactMap { $0.windowController as? BaseTerminalController }

        let document: [[String: Any]] = controllers.flatMap { controller in
            snapshot(controller: controller, focusedSurface: focusedSurface)
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        ), let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return json
    }

    private static func snapshot(
        controller: BaseTerminalController,
        focusedSurface: Ghostty.SurfaceView?
    ) -> [[String: Any]] {
        guard let window = controller.window else { return [] }
        guard let root = controller.surfaceTree.root else { return [] }

        let tabControllers: [BaseTerminalController]
        if let tabGroup = window.tabGroup {
            tabControllers = tabGroup.windows.compactMap { $0.windowController as? BaseTerminalController }
        } else {
            tabControllers = [controller]
        }

        let tabIndex = tabControllers.firstIndex(where: { $0 === controller }) ?? 0
        let tabTitle = controller.titleOverride ?? window.title

        // In AppKit's tabbed-window model every tab is its own NSWindow with a
        // distinct `windowNumber`. Grouping the flat snapshot back into windows
        // requires a stable ID shared by all tabs in the same tab group, so we
        // use the windowNumber of the first (primary) tab here. Fall back to
        // this tab's own windowNumber for single-window controllers.
        let groupWindowID = window.tabGroup?.windows.first?.windowNumber ?? window.windowNumber
        let groupWindowTitle = window.tabGroup?.windows.first?.title ?? window.title

        return root.leaves().map { view in
            let workingDirectory: Any = view.pwd ?? NSNull()
            var surface: [String: Any] = [
                "surface_id": view.id.uuidString,
                "window_id": groupWindowID,
                "window_title": groupWindowTitle,
                "tab_index": tabIndex,
                "tab_title": tabTitle,
                "split_path": splitPath(for: view, in: root),
                "pty_pid": NSNull(),
                "shell_pid": NSNull(),
                "working_directory": workingDirectory,
                "is_focused": focusedSurface === view,
            ]

            if let cSurface = view.surface {
                let shellPid = ghostty_surface_child_pid(cSurface)
                if shellPid > 0 {
                    surface["shell_pid"] = shellPid
                }
            }

            return surface
        }
    }

    private static func splitPath(
        for view: Ghostty.SurfaceView,
        in root: SplitTree<Ghostty.SurfaceView>.Node
    ) -> [Int] {
        guard let path = root.path(to: .leaf(view: view)) else { return [] }

        return path.path.map { component in
            switch component {
            case .left: 0
            case .right: 1
            }
        }
    }
}
