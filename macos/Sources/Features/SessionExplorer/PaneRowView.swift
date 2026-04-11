import SwiftUI

// ASSUMES:
// - `PaneDiff` exposes `positionLabel: String`, `workingDirectory: String`,
//   `processName: String`, and `status: DiffStatus`.
struct PaneRowView: View {
    let paneDiff: PaneDiff

    var body: some View {
        HStack(spacing: 12) {
            Text(paneDiff.positionLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.explorerMuted)
                .frame(width: 80, alignment: .leading)

            Text(paneDiff.workingDirectory)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.explorerMuted)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !paneDiff.processName.isEmpty {
                Text(paneDiff.processName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.explorerProcess.opacity(0.80))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.explorerProcess.opacity(0.15))
                    )
            }

            SessionExplorerStatusDot(status: paneDiff.status, size: 6)
        }
        .padding(.leading, 32)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }
}
