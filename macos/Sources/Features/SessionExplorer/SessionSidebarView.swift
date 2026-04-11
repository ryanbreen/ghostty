import SwiftUI

// ASSUMES:
// - `SessionStore.StoredSession` exposes `id`, `date`, `snapshot`, and `isLatest`.
// - `ExplorerSnapshot.windows` exists and each `ExplorerWindow` exposes `tabs`.
struct SessionSidebarView: View {
    @ObservedObject var store: SessionStore
    @Binding var selected: SessionStore.StoredSession?
    let onSnapshotCurrent: (() -> Void)?

    init(
        store: SessionStore,
        selected: Binding<SessionStore.StoredSession?>,
        onSnapshotCurrent: (() -> Void)? = nil
    ) {
        self.store = store
        self._selected = selected
        self.onSnapshotCurrent = onSnapshotCurrent
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedSessions.enumerated()), id: \.offset) { _, session in
                        Button {
                            selected = session
                        } label: {
                            SessionSidebarRowView(
                                session: session,
                                isSelected: selected?.id == session.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            footer
        }
        .background(Color.explorerSurface2)
    }

    private var sortedSessions: [SessionStore.StoredSession] {
        store.sessions.sorted { $0.date > $1.date }
    }

    private var header: some View {
        SessionExplorerHeaderLabel(text: "Sessions")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.explorerBorder)
                    .frame(height: 1)
            }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.explorerBorder)
                .frame(height: 1)

            Button("Snapshot Current") {
                onSnapshotCurrent?()
            }
            .buttonStyle(SessionExplorerOutlineButtonStyle(tint: .explorerAccent))
            .padding(12)
        }
        .background(Color.explorerSurface2)
    }
}

private struct SessionSidebarRowView: View {
    let session: SessionStore.StoredSession
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(SessionExplorerFormatters.sidebarTimestamp.string(from: session.date))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? Color.explorerAccent : Color.explorerText)

                Spacer(minLength: 8)

                if session.isLatest {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.explorerAccent)
                        .kerning(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.explorerAccent.opacity(0.15))
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.explorerAccent.opacity(0.30), lineWidth: 1)
                        }
                }
            }

            Text(summaryText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color.explorerMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? Color.explorerAccent : Color.clear)
                .frame(width: 2)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.explorerBorder.opacity(0.50))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var backgroundColor: Color {
        if isSelected { return .explorerSurface4 }
        if isHovering { return .explorerSurface3 }
        return .clear
    }

    private var summaryText: String {
        let windowCount = session.snapshot.windows.count
        let tabCount = session.snapshot.windows.reduce(0) { partialResult, window in
            partialResult + window.tabs.count
        }
        return "\(windowCount) windows, \(tabCount) tabs"
    }
}
