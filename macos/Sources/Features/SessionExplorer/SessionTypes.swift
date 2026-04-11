import Foundation

struct ExplorerSnapshot: Codable {
    let version: Int
    let windows: [ExplorerWindow]

    static let currentVersion = 1

    init(version: Int = Self.currentVersion, windows: [ExplorerWindow]) {
        self.version = version
        self.windows = windows
    }

    static func fromSurfaceListSnapshot(_ json: String) throws -> ExplorerSnapshot {
        let data = Data(json.utf8)
        let surfaces = try JSONDecoder().decode([LiveSurfaceRecord].self, from: data)
        return fromSurfaceListSnapshot(surfaces)
    }

    static func fromSurfaceListSnapshot(_ surfaces: [LiveSurfaceRecord]) -> ExplorerSnapshot {
        let groupedWindows = Dictionary(grouping: surfaces, by: \.windowID)

        let windows = groupedWindows.keys.sorted().compactMap { windowID -> ExplorerWindow? in
            guard let windowSurfaces = groupedWindows[windowID], !windowSurfaces.isEmpty else {
                return nil
            }

            let groupedTabs = Dictionary(grouping: windowSurfaces, by: \.tabIndex)
            let tabs = groupedTabs.keys.sorted().compactMap { tabIndex -> ExplorerTab? in
                guard let tabSurfaces = groupedTabs[tabIndex], !tabSurfaces.isEmpty else {
                    return nil
                }

                let title = tabSurfaces.compactMap(\.tabTitle).first(where: { !$0.isEmpty })
                let root = buildNode(from: tabSurfaces.map(LivePane.init))
                let surfaceTree = ExplorerSurfaceTree(root: root)
                return ExplorerTab(title: title, surfaceTree: surfaceTree)
            }

            let title = windowSurfaces.compactMap(\.windowTitle).first(where: { !$0.isEmpty })
            return ExplorerWindow(id: String(windowID), title: title, workspace: nil, tabs: tabs)
        }

        return ExplorerSnapshot(windows: windows)
    }

    private static func buildNode(from panes: [LivePane]) -> ExplorerSurfaceNode {
        guard !panes.isEmpty else {
            return .view(ExplorerSurfaceView())
        }

        if panes.count == 1, panes[0].path.isEmpty {
            return .view(panes[0].view)
        }

        let leftPanes = panes.compactMap { pane -> LivePane? in
            guard pane.path.first == 0 else { return nil }
            return pane.droppingFirstPathComponent()
        }
        let rightPanes = panes.compactMap { pane -> LivePane? in
            guard pane.path.first == 1 else { return nil }
            return pane.droppingFirstPathComponent()
        }

        if leftPanes.isEmpty, rightPanes.isEmpty {
            return .view(panes[0].view)
        }
        if leftPanes.isEmpty {
            return buildNode(from: rightPanes)
        }
        if rightPanes.isEmpty {
            return buildNode(from: leftPanes)
        }

        return .split(
            ExplorerSurfaceSplit(
                direction: "horizontal",
                ratio: 0.5,
                left: buildNode(from: leftPanes),
                right: buildNode(from: rightPanes)
            )
        )
    }
}

struct ExplorerWindow: Codable, Identifiable {
    let id: String
    let title: String?
    let workspace: Int?
    let tabs: [ExplorerTab]

    init(id: String, title: String? = nil, workspace: Int? = nil, tabs: [ExplorerTab]) {
        self.id = id
        self.title = title
        self.workspace = workspace
        self.tabs = tabs
    }
}

struct ExplorerTab: Codable {
    let title: String?
    let surfaceTree: ExplorerSurfaceTree

    init(title: String? = nil, surfaceTree: ExplorerSurfaceTree) {
        self.title = title
        self.surfaceTree = surfaceTree
    }
}

struct ExplorerSurfaceTree: Codable {
    let root: ExplorerSurfaceNode

    init(root: ExplorerSurfaceNode) {
        self.root = root
    }
}

indirect enum ExplorerSurfaceNode: Codable {
    case view(ExplorerSurfaceView)
    case split(ExplorerSurfaceSplit)

    private enum CodingKeys: String, CodingKey {
        case view
        case split
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.split) {
            self = .split(try container.decode(ExplorerSurfaceSplit.self, forKey: .split))
            return
        }

        if container.contains(.view) {
            self = .view(try container.decode(ExplorerSurfaceView.self, forKey: .view))
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .view,
            in: container,
            debugDescription: "ExplorerSurfaceNode must contain either a view or split payload."
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .view(let view):
            try container.encode(view, forKey: .view)
        case .split(let split):
            try container.encode(split, forKey: .split)
        }
    }
}

struct ExplorerSurfaceView: Codable {
    let id: String?
    let pwd: String?
    let title: String?
    let foregroundPid: Int?
    let foregroundProcess: String?
    let processExited: Bool?

    init(
        id: String? = nil,
        pwd: String? = nil,
        title: String? = nil,
        foregroundPid: Int? = nil,
        foregroundProcess: String? = nil,
        processExited: Bool? = nil
    ) {
        self.id = id
        self.pwd = pwd
        self.title = title
        self.foregroundPid = foregroundPid
        self.foregroundProcess = foregroundProcess
        self.processExited = processExited
    }
}

struct ExplorerSurfaceSplit: Codable {
    let direction: String
    let ratio: Double
    let left: ExplorerSurfaceNode
    let right: ExplorerSurfaceNode
}

extension ExplorerWindow {
    var displayTitle: String {
        firstNonEmpty(title, tabs.first?.title, id) ?? id
    }

    var normalizedTitle: String {
        displayTitle.normalizedForMatching
    }

    var tabDirectorySignatureSet: Set<String> {
        Set(tabs.map(\.workingDirectorySignature))
    }
}

extension ExplorerTab {
    var displayTitle: String {
        firstNonEmpty(title, workingDirectories.first, "Untitled Tab") ?? "Untitled Tab"
    }

    var workingDirectories: [String] {
        surfaceTree.root.flattenedPanes().compactMap(\.view.pwd)
    }

    var workingDirectorySignature: String {
        let directories = surfaceTree.root.flattenedPanes()
            .compactMap(\.view.pwd)
            .map(\.normalizedForMatching)
            .filter { !$0.isEmpty }
            .sorted()
        return directories.joined(separator: "|")
    }

    var splitSignature: [String] {
        surfaceTree.root.flattenedPanes()
            .map { $0.path.map(String.init).joined(separator: ".") }
            .sorted()
    }

    var paneCount: Int {
        surfaceTree.root.flattenedPanes().count
    }
}

extension ExplorerSurfaceNode {
    struct FlattenedPane {
        let view: ExplorerSurfaceView
        let position: String
        let path: [Int]
    }

    func flattenedPanes(prefix: String = "", path: [Int] = []) -> [FlattenedPane] {
        switch self {
        case .view(let view):
            return [FlattenedPane(view: view, position: prefix.isEmpty ? "root" : prefix, path: path)]
        case .split(let split):
            let leftLabel = split.direction == "vertical" ? "top" : "left"
            let rightLabel = split.direction == "vertical" ? "bottom" : "right"
            let leftPrefix = prefix.isEmpty ? leftLabel : "\(prefix)-\(leftLabel)"
            let rightPrefix = prefix.isEmpty ? rightLabel : "\(prefix)-\(rightLabel)"
            return split.left.flattenedPanes(prefix: leftPrefix, path: path + [0])
                + split.right.flattenedPanes(prefix: rightPrefix, path: path + [1])
        }
    }
}

struct LiveSurfaceRecord: Decodable {
    let surfaceID: String
    let windowID: Int
    let windowTitle: String?
    let tabIndex: Int
    let tabTitle: String?
    let splitPath: [Int]
    let shellPid: Int?
    let workingDirectory: String?

    private enum CodingKeys: String, CodingKey {
        case surfaceID = "surface_id"
        case windowID = "window_id"
        case windowTitle = "window_title"
        case tabIndex = "tab_index"
        case tabTitle = "tab_title"
        case splitPath = "split_path"
        case shellPid = "shell_pid"
        case workingDirectory = "working_directory"
    }
}

private struct LivePane {
    let path: [Int]
    let view: ExplorerSurfaceView

    init(record: LiveSurfaceRecord) {
        path = record.splitPath
        view = ExplorerSurfaceView(
            id: record.surfaceID,
            pwd: record.workingDirectory,
            title: record.tabTitle,
            foregroundPid: record.shellPid,
            foregroundProcess: nil,
            processExited: nil
        )
    }

    func droppingFirstPathComponent() -> LivePane {
        LivePane(path: Array(path.dropFirst()), view: view)
    }

    private init(path: [Int], view: ExplorerSurfaceView) {
        self.path = path
        self.view = view
    }
}

private func firstNonEmpty(_ values: String?...) -> String? {
    values.first(where: {
        guard let value = $0 else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) ?? nil
}

extension String {
    var normalizedForMatching: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
