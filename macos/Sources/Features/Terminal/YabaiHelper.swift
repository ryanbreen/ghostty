import AppKit

/// Lightweight interface to the yabai window manager.
/// Used by session snapshot (record workspace) and restore (place windows).

struct YabaiWindow: Decodable {
    let id: Int
    let pid: Int32
    let space: Int
    let frame: YabaiFrame

    struct YabaiFrame: Decodable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }
}

enum YabaiHelper {
    // MARK: - Binary Resolution

    static var executablePath: String? {
        let candidates = [
            "/opt/homebrew/bin/yabai",
            "/usr/local/bin/yabai",
            "/opt/local/bin/yabai",
        ]
        // Also check PATH
        let pathDirs = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":").map(String.init) ?? []
        let all = candidates + pathDirs.map { "\($0)/yabai" }
        return all.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Queries

    /// Returns all windows tracked by yabai.
    static func queryWindows() -> [YabaiWindow] {
        guard let path = executablePath,
              let data = run(path, args: ["-m", "query", "--windows"]) else { return [] }
        return (try? JSONDecoder().decode([YabaiWindow].self, from: data)) ?? []
    }

    /// Returns the yabai space index for the given NSWindow.
    static func space(for nsWindow: NSWindow) -> Int? {
        window(for: nsWindow)?.space
    }

    /// Returns the yabai window ID of our newest window (highest ID among our PID).
    static func newestOwnWindow() -> Int? {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        return queryWindows()
            .filter { $0.pid == ourPID }
            .max(by: { $0.id < $1.id })
            .map(\.id)
    }

    // MARK: - Commands

    /// Move a yabai window to a space by index.
    @discardableResult
    static func moveWindow(id: Int, toSpace space: Int) -> Bool {
        guard let path = executablePath else { return false }
        return run(path, args: ["-m", "window", "\(id)", "--space", "\(space)"]) != nil
    }

    /// Focus a space by index.
    @discardableResult
    static func focusSpace(_ space: Int) -> Bool {
        guard let path = executablePath else { return false }
        return run(path, args: ["-m", "space", "--focus", "\(space)"]) != nil
    }

    // MARK: - Private

    /// Match an AppKit window to yabai's window model.
    ///
    /// Yabai window ids line up with the CoreGraphics window id exposed by
    /// AppKit as `windowNumber`. Prefer that stable identity over titles or
    /// frames, because multiple Ghostty windows can share the same geometry.
    private static func window(for nsWindow: NSWindow) -> YabaiWindow? {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let windows = queryWindows().filter { $0.pid == ourPID }

        if let cgWindowId = nsWindow.cgWindowId,
           let exactMatch = windows.first(where: { $0.id == Int(cgWindowId) }) {
            return exactMatch
        }

        let frame = nsWindow.frame
        let frameMatches = windows.filter {
            abs($0.frame.x - Double(frame.origin.x)) < 10 &&
            abs($0.frame.y - Double(frame.origin.y)) < 10 &&
            abs($0.frame.w - Double(frame.size.width)) < 10 &&
            abs($0.frame.h - Double(frame.size.height)) < 10
        }

        // If geometry is ambiguous, prefer no workspace over a wrong one.
        guard frameMatches.count == 1 else { return nil }
        return frameMatches[0]
    }

    private static func run(_ path: String, args: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return stdout.fileHandleForReading.readDataToEndOfFile()
    }
}
