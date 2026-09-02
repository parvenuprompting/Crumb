import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var history: RunHistoryModel

    /// Oudste → nieuwste, zodat de insights-engine de meest recente vorige run pakt.
    private var orderedRuns: [ScanRun] { history.runs.reversed() }

    private var currentRun: ScanRun? { orderedRuns.last }

    private var privacyScore: PrivacyScore? {
        guard let currentRun else { return nil }
        return InsightsEngine.privacyScore(for: currentRun, priorRuns: Array(orderedRuns.dropLast()))
    }

    private var diff: CookieDiff? {
        guard let currentRun, orderedRuns.count >= 2 else { return nil }
        return InsightsEngine.diff(current: currentRun, prior: orderedRuns[orderedRuns.count - 2])
    }

    private var trendPoints: [TrendPoint] {
        orderedRuns.map { run in
            TrendPoint(
                date: run.finishedAt,
                tracking: run.records.filter { $0.category == .marketingTracking }.count,
                review: run.records.filter { $0.verdict != .keep }.count,
                total: run.records.count
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if history.runs.isEmpty {
                    Text("Nog geen run-geschiedenis. Elke scan wordt als JSON-rapport bewaard in ~/Library/Application Support/Crumb/logs/.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    scoreSection
                    trendCardsSection
                    chartsSection
                    sharingSection
                    churnSection
                    domainsSection
                    historySection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .onAppear { history.reload() }
    }

    // MARK: Privacy-score

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Privacy-score")
            if let score = privacyScore {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("\(score.score)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(score.label)
                            .font(.headline)
                        Text(score.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    // MARK: Trendkaarten

    private var trendCardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Verandering t.o.v. vorige run")
            HStack(alignment: .top, spacing: 12) {
                trendCard(
                    value: diff.map { "+\($0.newCookies.count)" } ?? "—",
                    label: "nieuwe cookies",
                    positive: (diff?.newCookies.count ?? 0) == 0
                )
                trendCard(
                    value: diff.map { "-\($0.disappearedCookies.count)" } ?? "—",
                    label: "verdwenen cookies",
                    positive: true
                )
                trendCard(
                    value: privacyScore.flatMap { score in
                        score.trackingDeltaPercent.map { String(format: "%+.0f%%", $0) }
                    } ?? "—",
                    label: "trackerdruk",
                    positive: (privacyScore?.trackingDelta ?? 0) <= 0
                )
                trendCard(
                    value: currentRun.map { "\($0.lockedCount)" } ?? "—",
                    label: "beschermde cookies",
                    positive: true
                )
            }
        }
    }

    private func trendCard(value: String, label: String, positive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(positive ? Color.secondary : CookieVerdict.reviewSuggested.semanticColor)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    // MARK: Grafieken

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tracking per run")
            Chart(trendPoints) { point in
                BarMark(
                    x: .value("Run", point.date),
                    y: .value("Aantal", point.tracking)
                )
                .foregroundStyle(.gray)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month())
                }
            }
            .frame(height: 160)

            Chart(trendPoints) { point in
                LineMark(
                    x: .value("Run", point.date),
                    y: .value("Totaal", point.total)
                )
                .foregroundStyle(.secondary)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month())
                }
            }
            .frame(height: 110)
            Text("Bovenin: marketing/tracking per run. Onderin: totaal aantal gescande cookies.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Browservergelijking

    private var sharingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Cross-browser duplicaten")
            let sharing = currentRun.map { InsightsEngine.browserSharing(in: $0).filter { $0.browserCount > 1 } } ?? []
            let inAll = currentRun.map { InsightsEngine.trackingInAllBrowsers(in: $0) } ?? []

            if let currentRun, Set(currentRun.records.map(\.browser)).count < 2 {
                Text("Er is maar één browser actief — vergelijken is nog niet mogelijk.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if sharing.isEmpty {
                Text("Geen cookies die in meerdere browsers voorkomen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if !inAll.isEmpty {
                    Text("\(inAll.count) tracking-cookies staan in ál je browsers tegelijk:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(inAll.prefix(8)) { entry in
                        HStack {
                            Text("\(entry.domain) · \(entry.name)")
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(entry.browsers.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider().opacity(0.3)
                }
                Text("Meest gedeelde cookies:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(sharing.prefix(10)) { entry in
                    HStack {
                        Text("\(entry.domain) · \(entry.name)")
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(entry.browserCount)×")
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: Churn

    private var churnSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Cookies met hoogste waarde-churn")
            if let currentRun, !InsightsEngine.topChurn(in: currentRun).isEmpty {
                ForEach(InsightsEngine.topChurn(in: currentRun)) { record in
                    HStack {
                        Text("\(record.domain) · \(record.name)")
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(record.valueChurn ?? 0)× ververst")
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(CookieVerdict.reviewSuggested.semanticColor)
                    }
                }
                Text("Hoge churn betekent dat de cookie telkens een nieuwe waarde krijgt — typisch voor actieve trackers.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Nog geen waardeveranderingen waargenomen (alleen zichtbaar bij Chromium-browsers).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Persistentie

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Meest hardnekkige tracking-domeinen (laatste runs)")
            let persistent = InsightsEngine.mostPersistentTrackingDomains(runs: orderedRuns)
            if persistent.isEmpty {
                Text("Nog geen tracking-cookies waargenomen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(persistent.prefix(10), id: \.domain) { entry in
                    StatRow(title: entry.domain, value: "\(entry.runs) runs", emphasized: entry.runs >= 3)
                }
            }
        }
    }

    // MARK: Geschiedenis

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Run-geschiedenis")
            ForEach(history.runs.prefix(12), id: \.startedAt) { run in
                HStack(alignment: .firstTextBaseline) {
                    Text(run.finishedAt.runTimestamp)
                        .font(.callout)
                        .monospacedDigit()
                    Spacer()
                    Text("\(run.records.count) cookies")
                        .font(.callout)
                        .monospacedDigit()
                    Text("\(run.records.filter { $0.category == .marketingTracking }.count) tracking")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                    Text(aiLabel(run))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if run.origin == "agent" {
                        Text("agent")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                Divider().opacity(0.4)
            }
        }
    }

    private func aiLabel(_ run: ScanRun) -> String {
        if let used = run.aiUsed, used {
            return "AI: \(run.aiClassifiedCount ?? 0) beoordeeld"
        }
        if run.aiSkippedReason != nil {
            return "AI overgeslagen"
        }
        return "alleen regellaag"
    }
}
