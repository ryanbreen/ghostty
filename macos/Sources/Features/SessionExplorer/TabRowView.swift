import SwiftUI

// ASSUMES:
// - `TabDiff` exposes `title: String`, `layoutDescription: String`, `status: DiffStatus`,
//   and `paneDiffs: [PaneDiff]`.
struct TabRowView: View {
    let index: Int
    let tabDiff: TabDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color.explorerMuted)
                    .frame(width: 24, alignment: .leading)

                Text(tabDiff.title)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color.explorerText)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(tabDiff.layoutDescription)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.explorerMuted)
                    .lineLimit(1)

                SessionExplorerStatusDot(status: tabDiff.status, size: 8)
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 8)

            if !tabDiff.paneDiffs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(tabDiff.paneDiffs.enumerated()), id: \.offset) { _, paneDiff in
                        PaneRowView(paneDiff: paneDiff)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }
}
