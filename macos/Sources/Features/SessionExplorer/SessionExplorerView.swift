import SwiftUI

struct SessionExplorerView: View {
    @StateObject private var store = SessionStore()
    @State private var selectedSession: SessionStore.StoredSession?
    @State private var diff: SessionDiff?
    @State private var liveState: ExplorerSnapshot?
    @State private var liveRefreshTask: Task<Void, Never>?

    let refreshLiveState: (() async -> ExplorerSnapshot?)?
    let computeDiff: ((SessionStore.StoredSession, ExplorerSnapshot?) -> SessionDiff?)?
    let onSnapshotCurrent: (() -> Void)?
    let onAssertAll: ((SessionStore.StoredSession) -> Void)?
    let onAssertWindow: ((SessionStore.StoredSession, WindowDiff) -> Void)?

    init(
        refreshLiveState: (() async -> ExplorerSnapshot?)? = nil,
        computeDiff: ((SessionStore.StoredSession, ExplorerSnapshot?) -> SessionDiff?)? = nil,
        onSnapshotCurrent: (() -> Void)? = nil,
        onAssertAll: ((SessionStore.StoredSession) -> Void)? = nil,
        onAssertWindow: ((SessionStore.StoredSession, WindowDiff) -> Void)? = nil
    ) {
        self.refreshLiveState = refreshLiveState
        self.computeDiff = computeDiff
        self.onSnapshotCurrent = onSnapshotCurrent
        self.onAssertAll = onAssertAll
        self.onAssertWindow = onAssertWindow
    }

    var body: some View {
        HSplitView {
            SessionSidebarView(
                store: store,
                selected: $selectedSession,
                onSnapshotCurrent: onSnapshotCurrent
            )
            .frame(minWidth: 250, idealWidth: 250, maxWidth: 250)
            .background(Color.explorerSurface2)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.explorerBorder)
                    .frame(width: 1)
            }

            SessionMainPanelView(
                session: selectedSession,
                diff: diff,
                onAssertAll: onAssertAll,
                onAssertWindow: onAssertWindow
            )
        }
        .frame(minWidth: 1020, minHeight: 700)
        .background(Color.explorerSurface1)
        .preferredColorScheme(.dark)
        .task {
            await handleInitialLoad()
        }
        .onDisappear {
            liveRefreshTask?.cancel()
            liveRefreshTask = nil
        }
        // ASSUMES: `StoredSession` exposes a stable `id` used for selection refresh.
        .onChange(of: selectedSession?.id) { _ in
            refreshDiff()
        }
        .onChange(of: store.sessions.count) { _ in
            if selectedSession == nil {
                selectedSession = sortedSessions.first
            }
            refreshDiff()
        }
    }

    private var sortedSessions: [SessionStore.StoredSession] {
        // ASSUMES: `StoredSession.date` is a `Date`.
        store.sessions.sorted { $0.date > $1.date }
    }

    @MainActor
    private func handleInitialLoad() async {
        store.loadSessions()
        if selectedSession == nil {
            selectedSession = sortedSessions.first
        }
        refreshDiff()
        startLiveRefreshLoop()
    }

    @MainActor
    private func refreshDiff() {
        guard let selectedSession, let computeDiff else {
            diff = nil
            return
        }
        diff = computeDiff(selectedSession, liveState)
    }

    @MainActor
    private func startLiveRefreshLoop() {
        liveRefreshTask?.cancel()
        guard let refreshLiveState else { return }

        liveRefreshTask = Task {
            await refreshLiveStateOnce(using: refreshLiveState)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await refreshLiveStateOnce(using: refreshLiveState)
            }
        }
    }

    private func refreshLiveStateOnce(using provider: @escaping () async -> ExplorerSnapshot?) async {
        let snapshot = await provider()
        await MainActor.run {
            liveState = snapshot
            refreshDiff()
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .clear
            return
        }

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        switch cleaned.count {
        case 8:
            alpha = Double((value & 0xFF000000) >> 24) / 255
            red = Double((value & 0x00FF0000) >> 16) / 255
            green = Double((value & 0x0000FF00) >> 8) / 255
            blue = Double(value & 0x000000FF) / 255
        case 6:
            alpha = 1
            red = Double((value & 0xFF0000) >> 16) / 255
            green = Double((value & 0x00FF00) >> 8) / 255
            blue = Double(value & 0x0000FF) / 255
        default:
            self = .clear
            return
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    static let explorerSurface1 = Color(hex: "#0f0f17")
    static let explorerSurface2 = Color(hex: "#13131e")
    static let explorerSurface3 = Color(hex: "#1a1a2e")
    static let explorerSurface4 = Color(hex: "#1e1e2e")
    static let explorerAccent = Color(hex: "#00d4aa")
    static let explorerBorder = Color(hex: "#252538")
    static let explorerText = Color(hex: "#e2e2f0")
    static let explorerMuted = Color(hex: "#6e6e88")
    static let explorerMatch = Color(hex: "#4ade80")
    static let explorerMissing = Color(hex: "#f87171")
    static let explorerPartial = Color(hex: "#fbbf24")
    static let explorerProcess = Color(hex: "#a5b4fc")
}

struct SessionExplorerStatusBadge: View {
    let status: DiffStatus

    var body: some View {
        let presentation = sessionExplorerStatusPresentation(for: status)

        Text(presentation.label)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(presentation.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(presentation.color.opacity(0.15))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(presentation.color.opacity(0.30), lineWidth: 1)
            }
    }
}

struct SessionExplorerWorkspaceBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.explorerMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.explorerSurface3.opacity(0.65))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.explorerBorder.opacity(0.85), lineWidth: 1)
            }
    }
}

struct SessionExplorerStatusDot: View {
    let status: DiffStatus
    let size: CGFloat

    init(status: DiffStatus, size: CGFloat = 8) {
        self.status = status
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(sessionExplorerStatusPresentation(for: status).color)
            .frame(width: size, height: size)
    }
}

struct SessionExplorerOutlineButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.16 : 0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(tint.opacity(configuration.isPressed ? 0.45 : 0.30), lineWidth: 1)
            }
    }
}

struct SessionExplorerFilledButtonStyle: ButtonStyle {
    let fill: Color
    let foreground: Color

    init(fill: Color, foreground: Color = .explorerSurface1) {
        self.fill = fill
        self.foreground = foreground
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.85 : 1))
            )
    }
}

struct SessionExplorerHeaderLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color.explorerMuted)
            .kerning(1.1)
            .textCase(.uppercase)
    }
}

struct SessionExplorerStatusPresentation {
    let label: String
    let color: Color
}

func sessionExplorerStatusPresentation(for status: DiffStatus) -> SessionExplorerStatusPresentation {
    // ASSUMES: `DiffStatus` contains `.match`, `.missing`, and `.partial`.
    switch status {
    case .match:
        SessionExplorerStatusPresentation(label: "Match", color: .explorerMatch)
    case .missing:
        SessionExplorerStatusPresentation(label: "Missing", color: .explorerMissing)
    case .partial:
        SessionExplorerStatusPresentation(label: "Partial", color: .explorerPartial)
    default:
        SessionExplorerStatusPresentation(label: "Unknown", color: .explorerMuted)
    }
}

func sessionExplorerIsMatch(_ status: DiffStatus) -> Bool {
    switch status {
    case .match:
        true
    default:
        false
    }
}

enum SessionExplorerFormatters {
    static let sidebarTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()

    static let headerTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' HH:mm"
        return formatter
    }()
}
