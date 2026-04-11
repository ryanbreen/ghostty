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

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case workspace
        case space
        case tabs
    }

    init(id: String, title: String? = nil, workspace: Int? = nil, tabs: [ExplorerTab]) {
        self.id = id
        self.title = title
        self.workspace = workspace
        self.tabs = tabs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        tabs = try container.decode([ExplorerTab].self, forKey: .tabs)
        workspace = try Self.decodeWorkspace(from: container)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(workspace, forKey: .workspace)
        try container.encode(tabs, forKey: .tabs)
    }

    private static func decodeWorkspace(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Int? {
        func decodeWorkspace(for key: CodingKeys) throws -> Int? {
            if let intValue = try? container.decode(Int.self, forKey: key) {
                return intValue
            }

            if let stringValue = try? container.decode(String.self, forKey: key) {
                return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            if let doubleValue = try? container.decode(Double.self, forKey: key) {
                return Int(doubleValue)
            }

            return nil
        }

        if let workspace = try decodeWorkspace(for: .workspace) {
            return workspace
        }

        return try decodeWorkspace(for: .space)
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
    /// Optional shell input that should be piped into the surface on startup
    /// (e.g. `"claude --resume <id>\n"`). Preserved through load/assert/restore
    /// so manual edits to saved snapshots survive the round-trip.
    let initialInput: String?
    /// Optional explicit command to launch instead of the user's default shell.
    let command: String?

    init(
        id: String? = nil,
        pwd: String? = nil,
        title: String? = nil,
        foregroundPid: Int? = nil,
        foregroundProcess: String? = nil,
        processExited: Bool? = nil,
        initialInput: String? = nil,
        command: String? = nil
    ) {
        self.id = id
        self.pwd = pwd
        self.title = title
        self.foregroundPid = foregroundPid
        self.foregroundProcess = foregroundProcess
        self.processExited = processExited
        self.initialInput = initialInput
        self.command = command
    }
}

struct ExplorerSurfaceSplit: Codable {
    let direction: String
    let ratio: Double
    let left: ExplorerSurfaceNode
    let right: ExplorerSurfaceNode

    private enum CodingKeys: String, CodingKey {
        case direction
        case ratio
        case left
        case right
    }

    init(direction: String, ratio: Double, left: ExplorerSurfaceNode, right: ExplorerSurfaceNode) {
        self.direction = direction
        self.ratio = ratio
        self.left = left
        self.right = right
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // SplitTree.Direction is encoded by Swift's synthesized Codable as a
        // tagged dict (e.g. {"horizontal": {}}). Older snapshots wrote a plain
        // string. Accept either form and normalize to a lowercased string.
        if let str = try? container.decode(String.self, forKey: .direction) {
            self.direction = str
        } else if let dict = try? container.decode([String: AnyCodable].self, forKey: .direction),
                  let key = dict.keys.first {
            self.direction = key
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .direction,
                in: container,
                debugDescription: "direction must be a string or tagged dict"
            )
        }
        self.ratio = try container.decode(Double.self, forKey: .ratio)
        self.left = try container.decode(ExplorerSurfaceNode.self, forKey: .left)
        self.right = try container.decode(ExplorerSurfaceNode.self, forKey: .right)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(direction, forKey: .direction)
        try container.encode(ratio, forKey: .ratio)
        try container.encode(left, forKey: .left)
        try container.encode(right, forKey: .right)
    }
}

/// Minimal Codable wrapper that lets us decode arbitrary JSON values when we
/// only need to peek at keys (used by ExplorerSurfaceSplit's tolerant
/// direction decoder).
private struct AnyCodable: Codable {
    init(from decoder: Decoder) throws {
        _ = try decoder.singleValueContainer()
    }
    func encode(to encoder: Encoder) throws {}
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
