import SwiftUI

// ASSUMES:
// - `SessionDiff` exposes `windowDiffs: [WindowDiff]`.
// - `StoredSession.date` is the persisted session timestamp.
struct SessionMainPanelView: View {
    let session: SessionStore.StoredSession?
    let diff: SessionDiff?
    let onAssertAll: ((SessionStore.StoredSession) -> Void)?
    let onAssertWindow: ((SessionStore.StoredSession, WindowDiff) -> Void)?

    init(
        session: SessionStore.StoredSession?,
        diff: SessionDiff?,
        onAssertAll: ((SessionStore.StoredSession) -> Void)? = nil,
        onAssertWindow: ((SessionStore.StoredSession, WindowDiff) -> Void)? = nil
    ) {
        self.session = session
        self.diff = diff
        self.onAssertAll = onAssertAll
        self.onAssertWindow = onAssertWindow
    }

    var body: some View {
        Group {
            if let session {
                VStack(spacing: 0) {
                    headerBar(session: session)

                    if primaryWindowDiffs.isEmpty {
                        placeholder(message: diff == nil ? "Waiting for live session state" : "No windows in this session")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(Array(primaryWindowDiffs.enumerated()), id: \.offset) { _, windowDiff in
                                    WindowCardView(windowDiff: windowDiff) {
                                        explorerDebugLog(
                                            "SessionMainPanelView forwarding assert window action: session_id=\(session.id) diff_id=\(windowDiff.id)"
                                        )
                                        onAssertWindow?(session, windowDiff)
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.explorerSurface1)
    }

    private var primaryWindowDiffs: [WindowDiff] {
        diff?.windows ?? []
    }

    private var matchingCount: Int {
        primaryWindowDiffs.reduce(into: 0) { count, windowDiff in
            if sessionExplorerIsMatch(windowDiff.status) {
                count += 1
            }
        }
    }

    private var missingCount: Int {
        primaryWindowDiffs.reduce(into: 0) { count, windowDiff in
            switch windowDiff.status {
            case .missing:
                count += 1
            default:
                break
            }
        }
    }

    private var partialCount: Int {
        primaryWindowDiffs.reduce(into: 0) { count, windowDiff in
            switch windowDiff.status {
            case .partial:
                count += 1
            default:
                break
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundColor(Color.explorerMuted)

            Text("Select a session to explore")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.explorerMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.explorerSurface1)
    }

    private func placeholder(message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundColor(Color.explorerMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func headerBar(session: SessionStore.StoredSession) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(SessionExplorerFormatters.headerTimestamp.string(from: session.date))
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(Color.explorerText)

                diffSummary
            }

            Spacer(minLength: 16)

            Button("Assert All") {
                explorerDebugLog(
                    "Assert All button tapped: session_id=\(session.id) windows=\(session.snapshot.windows.count)"
                )
                onAssertAll?(session)
            }
            .buttonStyle(SessionExplorerFilledButtonStyle(fill: .explorerAccent))
        }
        .padding(16)
        .background(Color.explorerSurface2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.explorerBorder)
                .frame(height: 1)
        }
    }

    private var diffSummary: some View {
        var text =
            Text("\(missingCount)")
                .foregroundColor(Color.explorerMissing)
            + Text(" missing, ")
                .foregroundColor(Color.explorerMuted)
            + Text("\(matchingCount)")
                .foregroundColor(Color.explorerMatch)
            + Text(" matching")
                .foregroundColor(Color.explorerMuted)

        if partialCount > 0 {
            text = text
                + Text(", ")
                    .foregroundColor(Color.explorerMuted)
                + Text("\(partialCount)")
                    .foregroundColor(Color.explorerPartial)
                + Text(" partial")
                    .foregroundColor(Color.explorerMuted)
        }

        return text
            .font(.system(size: 12, design: .monospaced))
    }
}
