import SwiftUI

// ASSUMES:
// - `WindowDiff` exposes `title: String`, `status: DiffStatus`, and `tabDiffs: [TabDiff]`.
struct WindowCardView: View {
    let windowDiff: WindowDiff
    let onAssertWindow: (() -> Void)?

    @State private var isExpanded = false
    @State private var isHovering = false

    init(windowDiff: WindowDiff, onAssertWindow: (() -> Void)? = nil) {
        self.windowDiff = windowDiff
        self.onAssertWindow = onAssertWindow
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            .background(isHovering ? Color.explorerSurface3.opacity(0.35) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
            .onHover { hovering in
                isHovering = hovering
            }

            if isExpanded {
                Rectangle()
                    .fill(Color.explorerBorder)
                    .frame(height: 1)

                VStack(spacing: 0) {
                    ForEach(Array(windowDiff.tabDiffs.enumerated()), id: \.offset) { index, tabDiff in
                        TabRowView(index: index + 1, tabDiff: tabDiff)

                        if index < windowDiff.tabDiffs.count - 1 {
                            Rectangle()
                                .fill(Color.explorerBorder.opacity(0.50))
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.explorerSurface1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.explorerBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.explorerMuted)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.15), value: isExpanded)

            HStack(spacing: 0) {
                Text(windowDiff.title)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.explorerText)

                Text(" — \(windowDiff.tabDiffs.count) \(windowDiff.tabDiffs.count == 1 ? "tab" : "tabs")")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color.explorerMuted)
            }

            Spacer(minLength: 16)

            SessionExplorerStatusBadge(status: windowDiff.status)

            if !sessionExplorerIsMatch(windowDiff.status) {
                Button("Assert Window") {
                    explorerDebugLog(
                        "Assert Window button tapped: diff_id=\(windowDiff.id) title=\(windowDiff.title) status=\(String(describing: windowDiff.status))"
                    )
                    onAssertWindow?()
                }
                .buttonStyle(SessionExplorerOutlineButtonStyle(tint: .explorerAccent))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
