import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var scanService: ScanService
    @EnvironmentObject private var history: RunHistoryModel

    @State private var selectedPreset: QuickCleanPreset?
    @State private var targetsForDeletion: [CookieRecord] = []
    @State private var showDeleteConfirmation = false
    @State private var deleteResults: [DeletionResult]?
    @State private var isDeleting = false
    @State private var recentAudit: [AuditEntry] = []

    private var run: ScanRun? { scanService.lastRun }

    private var recommendations: [CookieRecommendation] {
        guard let run else { return [] }
        return RecommendationEngine.recommendations(for: run, history: history.runs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                accessSection

                if scanService.isScanning {
                    ScanProgressSection()
                } else if let run {
                    dashboardSection(run)
                    recommendationsSection
                    Divider().opacity(0.3)
                    quickCleanSection(run)
                    Divider().opacity(0.3)
                    HStack(alignment: .top, spacing: 24) {
                        browserSection(run)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        recentActivitySection
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showDeleteConfirmation) {
            DeleteConfirmationSheet(
                records: targetsForDeletion,
                results: deleteResults,
                isDeleting: isDeleting,
                onConfirm: { executeQuickClean() },
                onCancel: {
                    showDeleteConfirmation = false
                    deleteResults = nil
                    selectedPreset = nil
                    targetsForDeletion = []
                }
            )
        }
        .onAppear {
            history.reload()
            recentAudit = AuditLog.allEntries(limit: 5)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scanService.lastRun == nil
                 ? "Nog geen scan uitgevoerd."
                 : "Geen resultaten.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Scan nu") {
                Task { await scanService.runScan() }
            }
        }
    }

    // MARK: - Dashboard

    private func dashboardSection(_ run: ScanRun) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionHeader(title: "Privacy-overzicht")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(run.finishedAt.runTimestamp)
                            .font(.callout.weight(.semibold))
                        if run.origin == "agent" {
                            Text("Achtergrond-agent")
                                .font(.caption.weight(.semibold))
                                .tracking(0.04)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button {
                    Task { await scanService.runScan() }
                } label: {
                    Text(scanService.isScanning ? "Bezig…" : "Scan nu")
                }
                .disabled(scanService.isScanning)
            }

            HStack(alignment: .top, spacing: 12) {
                dashboardCard(value: "\(run.records.count)", label: "cookies totaal", color: .primary)
                dashboardCard(
                    value: "\(run.verdictCounts[.safeToClean, default: 0])",
                    label: "veilig op te ruimen",
                    color: CookieVerdict.safeToClean.semanticColor
                )
                dashboardCard(value: "\(run.lockedCount)", label: "beschermd", color: .primary)
                dashboardCard(
                    value: "\(run.categoryCounts[.marketingTracking, default: 0])",
                    label: "tracking-cookies",
                    color: CookieVerdict.reviewSuggested.semanticColor
                )
                Spacer()
                primaryCleanButton(run)
            }
        }
    }

    private func dashboardCard(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(minWidth: 130, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private func primaryCleanButton(_ run: ScanRun) -> some View {
        let candidates = run.records.filter { $0.verdict == .safeToClean && !$0.protection.isLocked }
        return Button {
            guard !candidates.isEmpty else { return }
            selectedPreset = .allSafeToClean
            targetsForDeletion = candidates
            deleteResults = nil
            showDeleteConfirmation = true
        } label: {
            VStack(spacing: 2) {
                Label("Veilig opschonen", systemImage: "sparkles")
                    .font(.callout.weight(.semibold))
                Text("\(candidates.count) cookies")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.primary)
        .disabled(candidates.isEmpty)
        .frame(maxWidth: 170, minHeight: 52)
    }

    // MARK: - Aanbevelingen

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Aanbevolen — gesorteerd op impact")
            if recommendations.isEmpty {
                Text("Geen openstaande aanbevelingen — alles is beoordeeld of schoon.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recommendations) { recommendation in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: recommendation.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recommendation.title)
                                .font(.callout.weight(.semibold))
                            Text(recommendation.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.3)
                }
            }
        }
    }

    // MARK: - Scanvoortgang

    struct ScanProgressSection: View {
        @EnvironmentObject private var scanService: ScanService

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Scan loopt")
                let steps: [ScanPhase] = [.detectingBrowsers, .readingStores, .applyingRules, .aiClassification, .checkingSafelist, .savingReport]
                let current = scanService.phase

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(steps, id: \.self) { step in
                        let index = steps.firstIndex(of: step) ?? 0
                        let currentIndex = steps.firstIndex(of: current) ?? -1
                        HStack(spacing: 8) {
                            if index < currentIndex {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            } else if step == current {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.tertiary)
                            }
                            Text(step.displayName)
                                .font(.callout)
                                .foregroundStyle(step == current ? .primary : (index < currentIndex ? .secondary : .tertiary))
                            Spacer()
                        }
                    }
                }

                if !scanService.liveSourceStatuses.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(scanService.liveSourceStatuses, id: \.browser) { status in
                            HStack {
                                Image(systemName: status.scanned ? "checkmark.circle" : (status.requiresFullDiskAccess ? "lock" : "exclamationmark.triangle"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(status.browser)
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Text(status.scanned
                                     ? "\(status.cookieCount) cookies"
                                     : (status.error ?? "overgeslagen"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }
            }
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
        }
    }

    // MARK: - Quick clean

    private func quickCleanSection(_ run: ScanRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Snelkeuzes")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(QuickCleanPreset.allCases) { preset in
                    let candidates = QuickCleanEngine.candidates(for: preset, in: run)
                    QuickCleanCardView(
                        preset: preset,
                        count: candidates.count,
                        onAction: {
                            guard !candidates.isEmpty else { return }
                            selectedPreset = preset
                            targetsForDeletion = candidates
                            deleteResults = nil
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
        }
    }

    private func executeQuickClean() {
        guard let preset = selectedPreset, !targetsForDeletion.isEmpty else { return }
        isDeleting = true
        Task { @MainActor in
            let results = await QuickCleanEngine.delete(records: targetsForDeletion, preset: preset)
            isDeleting = false
            deleteResults = results
            await scanService.runScan()
            recentAudit = AuditLog.allEntries(limit: 5)
        }
    }

    // MARK: - Toegang

    private var accessSection: some View {
        let blocked = scanService.sourceAvailability.filter { $0.isInstalled && (!$0.isAccessible) }
        return Group {
            if !blocked.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Toegang vereist")
                    ForEach(blocked) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(source.browser) kan niet worden gelezen.")
                                .font(.callout.weight(.semibold))
                            Text("Geef Crumb Volledige Schijftoegang in Systeeminstellingen → Privacy & Beveiliging → Volledige Schijftoegang en start daarna Crumb opnieuw.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Systeeminstellingen openen") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Bronnen + recente activiteit

    private func browserSection(_ run: ScanRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Bronnen")
            ForEach(run.sources, id: \.browser) { source in
                StatRow(
                    title: source.browser,
                    value: source.scanned
                        ? "\(source.cookieCount) cookies"
                        : (source.error ?? "niet aanwezig")
                )
            }
        }
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Recente activiteit")
            if recentAudit.isEmpty {
                Text("Nog geen verwijderingen uitgevoerd.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(recentAudit.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text("\(entry.domain) · \(entry.name)")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(entry.result == "deleted" ? "verwijderd" : "mislukt")
                                .font(.caption2)
                                .foregroundStyle(entry.result == "deleted" ? CookieVerdict.safeToClean.semanticColor : CookieVerdict.reviewSuggested.semanticColor)
                        }
                        Text("\(entry.mode) · \(entry.timestamp.ageDescription)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}
