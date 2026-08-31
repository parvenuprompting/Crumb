import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var history: RunHistoryModel

    private var trendPoints: [TrendPoint] {
        history.runs.map { run in
            TrendPoint(
                date: run.finishedAt,
                tracking: run.records.filter { $0.category == .marketingTracking }.count,
                review: run.records.filter { $0.verdict != .keep }.count,
                total: run.records.count
            )
        }
    }

    private var topTrackingDomains: [(domain: String, count: Int)] {
        var counts: [String: Int] = [:]
        for run in history.runs.suffix(10) {
            for record in run.records where record.category == .marketingTracking {
                counts[record.domain, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if history.runs.isEmpty {
                    Text("Nog geen run-geschiedenis. Elke scan wordt als JSON-rapport bewaard in ~/Library/Application Support/Crumb/logs/.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    chartSection
                    historySection
                    domainsSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .onAppear { history.reload() }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tracking-cookies per run")
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
            .frame(height: 180)

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
            .frame(height: 120)
            Text("Bovenin: marketing/tracking per run. Onderin: totaal aantal gescande cookies.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

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
                }
                .padding(.vertical, 2)
                Divider().opacity(0.4)
            }
        }
    }

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Meest terugkerende tracking-domeinen (laatste 10 runs)")
            if topTrackingDomains.isEmpty {
                Text("Nog geen tracking-cookies waargenomen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(topTrackingDomains, id: \.domain) { entry in
                    StatRow(title: entry.domain, value: "\(entry.count)×", emphasized: entry.count >= 3)
                }
            }
        }
    }

    private func aiLabel(_ run: ScanRun) -> String {
        if let used = run.aiUsed, used {
            return "AI: \(run.aiClassifiedCount ?? 0) beoordeeld"
        }
        if let reason = run.aiSkippedReason {
            return "AI overgeslagen"
        }
        return "alleen regellaag"
    }
}
