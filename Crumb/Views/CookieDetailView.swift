import SwiftUI

/// Detailpaneel voor één cookie: volledige metadata, uitleg per bescherming/
/// verdict, classificatie, vergelijkbare cookies en acties.
struct CookieDetailView: View {
    let record: CookieRecord
    let allRecords: [CookieRecord]
    let onWhitelistDomain: (String) -> Void
    let onProtectToggle: (CookieRecord) -> Void
    let onDelete: (CookieRecord) -> Void
    let onSelectSimilar: (CookieRecord) -> Void

    @State private var isProtectedNow = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                whySection
                metadataSection
                classificationSection
                similarSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { isProtectedNow = ProtectedCookieStore.load().contains(domain: record.domain, name: record.name, path: record.path) }
    }

    private var sameCookieElsewhere: [CookieRecord] {
        allRecords.filter {
            $0.domain == record.domain && $0.name == record.name && $0.path == record.path && $0.browser != record.browser
        }
    }

    private var similarOnDomain: [CookieRecord] {
        allRecords.filter {
            $0.domain == record.domain && $0.id != record.id
        }
        .sorted { a, b in
            if a.name != b.name { return a.name < b.name }
            return a.browser < b.browser
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.name)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                Text(record.domain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
            }

            HStack(spacing: 8) {
                verdictBadge
                if record.protection.isLocked {
                    Label(record.protection.shortLabel, systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if record.protection.isReviewOnly {
                    Label(record.protection.shortLabel, systemImage: "eye")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                actionButton("Verwijderen", icon: "trash", enabled: !record.protection.isLocked) {
                    onDelete(record)
                }
                actionButton("Whitelist domein", icon: "checkmark.shield", enabled: true) {
                    onWhitelistDomain(record.domain)
                }
                actionButton(
                    isProtectedNow ? "Bescherming opheffen" : "Deze cookie beschermen",
                    icon: isProtectedNow ? "lock.open" : "lock",
                    enabled: true
                ) {
                    onProtectToggle(record)
                    isProtectedNow.toggle()
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private var verdictBadge: some View {
        Label(record.verdict.displayName, systemImage: record.verdict.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(record.verdict.semanticColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(record.verdict.semanticColor.opacity(0.10)))
    }

    private var whySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Waarom dit advies?")
            Text(ProtectionExplanation.explain(record))
                .font(.callout)
            Text(record.reasoning)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Details")
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow {
                    Text("Browsers").foregroundStyle(.secondary)
                    Text(browsersDescription)
                }
                GridRow {
                    Text("Eerst gezien").foregroundStyle(.secondary)
                    Text("\(record.firstSeen.formatted(date: .long, time: .omitted)) · \(record.firstSeen.ageDescription)")
                }
                GridRow {
                    Text("Laatst gezien").foregroundStyle(.secondary)
                    Text(record.lastSeen.formatted(date: .long, time: .omitted))
                }
                GridRow {
                    Text("Vervalt").foregroundStyle(.secondary)
                    Text(record.isSessionOnly
                         ? "sessiecookie (vervalt bij sluiten browser)"
                         : record.expiry.map { $0.formatted(date: .long, time: .omitted) } ?? "onbekend")
                }
                GridRow {
                    Text("Vlaggen").foregroundStyle(.secondary)
                    Text(flagDescription)
                }
                if let churn = record.valueChurn, churn > 0 {
                    GridRow {
                        Text("Waarde-churn").foregroundStyle(.secondary)
                        Text("\(churn)× ververst sinds eerste waarneming")
                    }
                }
                GridRow {
                    Text("Pad").foregroundStyle(.secondary)
                    Text(record.path).monospaced()
                }
            }
            .font(.callout)
        }
    }

    private var browsersDescription: String {
        let browsers = ([record.browser] + sameCookieElsewhere.map(\.browser)).sorted()
        return browsers.joined(separator: ", ")
    }

    private var flagDescription: String {
        var parts: [String] = []
        parts.append(record.isSecure ? "secure" : "geen secure")
        parts.append(record.isHttpOnly ? "httpOnly" : "geen httpOnly")
        return parts.joined(separator: " · ")
    }

    private var classificationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Classificatie")
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow {
                    Text("Categorie").foregroundStyle(.secondary)
                    Text(record.category.displayName)
                }
                GridRow {
                    Text("Advies").foregroundStyle(.secondary)
                    Text(record.verdict.displayName)
                }
            }
            .font(.callout)

            if record.reasoning.contains("AI:") {
                Text("Het lokale LLM heeft dit cookie beoordeeld (alleen metadata, geen waarde).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Vergelijkbare cookies op \(record.domain)")
            if !sameCookieElsewhere.isEmpty {
                Text("Deze cookie staat ook in: \(browsersDescription).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if similarOnDomain.isEmpty {
                Text("Geen andere cookies op dit domein.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(similarOnDomain.prefix(12)) { other in
                    Button {
                        onSelectSimilar(other)
                    } label: {
                        HStack {
                            Text(other.name)
                                .font(.callout.weight(.medium))
                            Text(other.browser)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: other.verdict.systemImage)
                                .font(.caption)
                                .foregroundStyle(other.verdict.semanticColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .disabled(!enabled)
        .controlSize(.small)
    }
}
