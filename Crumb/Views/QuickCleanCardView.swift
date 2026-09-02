import SwiftUI

struct QuickCleanCardView: View {
    let preset: QuickCleanPreset
    let count: Int
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 36, height: 36)
                    Image(systemName: preset.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("\(count)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text("cookies")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(count > 0 ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(preset.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(preset.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(action: onAction) {
                HStack(spacing: 6) {
                    if count > 0 {
                        Image(systemName: "trash")
                            .font(.caption2)
                        Text("Nu opschonen")
                    } else {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                        Text("Alles schoon")
                    }
                }
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .foregroundStyle(count > 0 ? AnyShapeStyle(.background) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderedProminent)
            .tint(count > 0 ? Color.primary : Color.secondary.opacity(0.3))
            .disabled(count == 0)
            .controlSize(.regular)
        }
        .padding(16)
        .frame(minHeight: 165)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
