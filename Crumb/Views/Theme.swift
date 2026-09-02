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

extension CookieVerdict {
    /// Subtiele semantische accenten — het ontwerp blijft monochroom, kleur
    /// draagt alleen betekenis en komt altijd naast een icoon/label.
    var semanticColor: Color {
        switch self {
        case .safeToClean: return Color(red: 0.18, green: 0.52, blue: 0.28)
        case .reviewSuggested: return Color(red: 0.78, green: 0.48, blue: 0.08)
        case .keep: return .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .safeToClean: return "checkmark.circle"
        case .reviewSuggested: return "exclamationmark.circle"
        case .keep: return "circle"
        }
    }
}

extension CookieProtection {
    var shortLabel: String {
        switch self {
        case .locked: return "BESCHERMD"
        case .reviewOnly: return "REVIEW"
        case .none: return ""
        }
    }
}

extension Date {
    var runTimestamp: String {
        formatted(date: .abbreviated, time: .shortened)
    }

    var ageDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
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
