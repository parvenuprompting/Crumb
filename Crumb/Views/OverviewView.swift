import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var scanService: ScanService

    @State private var selectedPreset: QuickCleanPreset?
    @State private var targetsForDeletion: [CookieRecord] = []
    @State private var showDeleteConfirmation = false
    @State private var deleteResults: [DeletionResult]?
    @State private var isDeleting = false

    private var run: ScanRun? { scanService.lastRun }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                accessSection
                headerSection

                if let run {
                    quickCleanSection(run)

                    Divider().opacity(0.3)

                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 16) {
                            categorySection(run)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 16) {
                            verdictSection(run)
                            browserSection(run)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(scanService.isScanning
                         ? "Eerste scan loopt…"
                         : "Nog geen scan uitgevoerd. Gebruik 'Scan nu'.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
    }

    private func quickCleanSection(_ run: ScanRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Snelkeuzes — 1-klik opschonen")
                Spacer()
                let totalSafe = run.verdictCounts[.safeToClean, default: 0]
                if totalSafe > 0 {
                    Text("\(totalSafe) cookies direct veilig te verwijderen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(QuickCleanPreset.allCases) { preset in
                    let candidates = QuickCleanEngine.candidates(for: preset, in: run)
                    QuickCleanCardView(
                        preset: preset,
                        count: candidates.count,
                        onAction: {
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
        }
    }

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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionHeader(title: "Laatste run")
                    if let run {
                        Text(run.finishedAt.runTimestamp)
                            .font(.title3.weight(.semibold))
                        Text("Duur: \(String(format: "%.1f", run.finishedAt.timeIntervalSince(run.startedAt))) s · \(run.records.count) cookies")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .font(.title3)
                            .foregroundStyle(.secondary)
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

            if let error = scanService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let run {
                if let used = run.aiUsed, used {
                    Text("AI-classificatie actief — \(run.aiClassifiedCount ?? 0) twijfelgevallen beoordeeld door het lokale model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let reason = run.aiSkippedReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("AI-classificatie uit — adviezen komen alleen uit de regellaag.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func categorySection(_ run: ScanRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Categorieën")
            ForEach(CookieCategory.allCases, id: \.self) { category in
                let count = run.categoryCounts[category, default: 0]
                if count > 0 {
                    StatRow(title: category.displayName, value: "\(count)", emphasized: category == .marketingTracking)
                }
            }
        }
    }

    private func verdictSection(_ run: ScanRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Adviezen")
            ForEach(CookieVerdict.allCases, id: \.self) { verdict in
                let count = run.verdictCounts[verdict, default: 0]
                if count > 0 || verdict == .reviewSuggested {
                    StatRow(
                        title: verdict.displayName,
                        value: "\(count)",
                        emphasized: verdict != .keep
                    )
                }
            }
            StatRow(title: "Geblokkeerd door safelist", value: "\(run.lockedCount)", emphasized: true)
        }
    }

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
}
