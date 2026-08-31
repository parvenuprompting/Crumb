import SwiftUI

enum Mono {
    static func categoryLabel(_ category: CookieCategory) -> String {
        category.rawValue.uppercased().replacingOccurrences(of: "TRACKING", with: "TRACKING")
    }

    static func verdictWeight(_ verdict: CookieVerdict) -> Font.Weight {
        switch verdict {
        case .keep: return .regular
        case .reviewSuggested: return .medium
        case .safeToClean: return .semibold
        }
    }
}

extension Date {
    var runTimestamp: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}

struct StatRow: View {
    let title: String
    let value: String
    var emphasized = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.weight(emphasized ? .semibold : .regular))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .tracking(0.06)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}
