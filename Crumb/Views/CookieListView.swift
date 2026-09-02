import SwiftUI

struct CookieListView: View {
    @EnvironmentObject private var scanService: ScanService
    @EnvironmentObject private var whitelist: WhitelistModel
    @State private var searchText = ""
    @State private var browserFilter = "Alle"
    @State private var categoryFilter = "Alle"
    @State private var verdictFilter = "Alle"
    @State private var selection = Set<String>()
    @State private var pendingDeleteTargets: [CookieRecord] = []
    @State private var showDeleteConfirmation = false
    @State private var deleteResults: [DeletionResult]?
    @State private var isDeleting = false
    @State private var whitelistNotice: String?

    private var records: [CookieRecord] {
        scanService.lastRun?.records ?? []
    }

    private var availableBrowsers: [String] {
        Array(Set(records.map(\.browser))).sorted()
    }

    private var filtered: [CookieRecord] {
        records.filter { record in
            if browserFilter != "Alle", record.browser != browserFilter { return false }
            if categoryFilter != "Alle", record.category.displayName != categoryFilter { return false }
            if verdictFilter != "Alle", record.verdict.displayName != verdictFilter { return false }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                if !record.domain.lowercased().contains(query),
                   !record.name.lowercased().contains(query) {
                    return false
                }
            }
            return true
        }
        .sorted { a, b in
            if a.domain != b.domain { return a.domain < b.domain }
            return a.name < b.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {                Picker("", selection: $browserFilter) {
                    Text("Alle").tag("Alle")
                    ForEach(availableBrowsers, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)

                Picker("", selection: $categoryFilter) {
                    Text("Alle").tag("Alle")
                    ForEach(CookieCategory.allCases, id: \.self) { category in
                        Text(category.displayName).tag(category.displayName)
                    }
                }
                .labelsHidden()
                .frame(width: 170)

                Picker("", selection: $verdictFilter) {
                    Text("Alle").tag("Alle")
                    ForEach(CookieVerdict.allCases, id: \.self) { verdict in
                        Text(verdict.displayName).tag(verdict.displayName)
                    }
                }
                .labelsHidden()
                .frame(width: 170)

                Spacer()
                Text("\(filtered.count) van \(records.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Button("Verwijderen…") {
                    pendingDeleteTargets = filtered.filter { selection.contains($0.id) }
                    deleteResults = nil
                    showDeleteConfirmation = true
                }
                .disabled(selection.isEmpty)
                .controlSize(.small)
            }

            if let whitelistNotice {
                Text(whitelistNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if filtered.isEmpty {
                Text(scanService.lastRun == nil
                     ? "Nog geen scan uitgevoerd."
                     : "Geen cookies matchen de filters.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(selection: $selection) {
                    ForEach(filtered) { record in
                        CookieRow(record: record)
                            .tag(record.id)
                            .contextMenu {
                                Button("Verwijderen…") {
                                    pendingDeleteTargets = [record]
                                    deleteResults = nil
                                    showDeleteConfirmation = true
                                }
                                .disabled(record.protection.isLocked)

                                Button("Voeg '\(record.domain)' toe aan whitelist") {
                                    if let message = whitelist.add(record.domain) {
                                        showWhitelistNotice(message)
                                    } else {
                                        showWhitelistNotice("'\(record.domain)' staat op de whitelist — beschermd na de volgende scan.")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Zoek op domein of naam")
        .sheet(isPresented: $showDeleteConfirmation) {
            DeleteConfirmationSheet(
                records: pendingDeleteTargets,
                results: deleteResults,
                isDeleting: isDeleting,
                onConfirm: { deleteTargets(pendingDeleteTargets) },
                onCancel: {
                    showDeleteConfirmation = false
                    deleteResults = nil
                }
            )
        }
    }

    private func showWhitelistNotice(_ message: String) {
        whitelistNotice = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if whitelistNotice == message { whitelistNotice = nil }
        }
    }

    private func deleteTargets(_ targets: [CookieRecord]) {
        guard !targets.isEmpty else { return }
        isDeleting = true
        Task { @MainActor in
            let results = await DeletionEngine.delete(targets)
            let entries: [AuditEntry] = results.map { result in
                AuditEntry(
                    timestamp: Date(),
                    mode: "manual",
                    browser: result.record.browser,
                    domain: result.record.domain,
                    name: result.record.name,
                    path: result.record.path,
                    category: result.record.category.rawValue,
                    verdict: result.record.verdict.rawValue,
                    reasoning: result.record.reasoning,
                    result: result.success ? "deleted" : "failed",
                    detail: result.detail
                )
            }
            try? AuditLog.append(entries)
            isDeleting = false
            deleteResults = results
            await scanService.runScan()
            selection.removeAll()
        }
    }
}

struct DeleteConfirmationSheet: View {
    let records: [CookieRecord]
    let results: [DeletionResult]?
    let isDeleting: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(results == nil ? "Stap 1 — bevestig je selectie" : "Stap 2 — resultaat")
                .font(.headline)

            if let results {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(results, id: \.record.id) { result in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("\(result.record.name) · \(result.record.domain)")
                                        .font(.callout.weight(.medium))
                                    Spacer()
                                    Text(result.success ? "VERWIJDERD" : "GEFAALD")
                                        .font(.caption2.weight(.semibold))
                                }
                                Text(result.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            Divider().opacity(0.4)
                        }
                    }
                }
                .frame(maxHeight: 260)

                HStack {
                    Spacer()
                    Button("Sluiten") { onCancel() }
                }
            } else {
                Text("\(records.count) cookie(s) geselecteerd. Safelist-cookies worden geweigerd; browsers moeten gesloten zijn.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("\(record.name) · \(record.domain)")
                                        .font(.callout.weight(.medium))
                                    Spacer()
                                    Text(DeletionEngine.canDelete(record).allowed ? "" : "GEBLOKKEERD")
                                        .font(.caption2.weight(.semibold))
                                }
                                Text(record.reasoning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            Divider().opacity(0.4)
                        }
                    }
                }
                .frame(maxHeight: 260)

                HStack {
                    Button("Annuleren") { onCancel() }
                    Spacer()
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Definitief verwijderen") {
                        onConfirm()
                    }
                    .disabled(records.isEmpty || isDeleting || records.contains { !DeletionEngine.canDelete($0).allowed })
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

struct CookieRow: View {
    let record: CookieRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.name)
                    .font(.callout.weight(.semibold))
                    .textSelection(.enabled)
                Text(record.domain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Text(record.category.rawValue.uppercased())
                    .font(.caption2.weight(.medium))
                    .tracking(0.04)
                    .foregroundStyle(.secondary)
                Text(record.verdict.displayName.uppercased())
                    .font(.caption2.weight(Mono.verdictWeight(record.verdict)))
                    .tracking(0.04)
            }

            Text(record.reasoning)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Text(record.browser)
                Text("secure: \(record.isSecure ? "ja" : "nee")")
                Text("httpOnly: \(record.isHttpOnly ? "ja" : "nee")")
                Text(record.isSessionOnly ? "sessie" : "persistent")
                if let expiry = record.expiry {
                    Text("vervalt: \(expiry.formatted(date: .numeric, time: .omitted))")
                }
                Text("eerst gezien: \(record.firstSeen.formatted(date: .numeric, time: .omitted))")
                if let churn = record.valueChurn, churn > 0 {
                    Text("waarde \(churn)× ververst")
                }
                if record.protection.isLocked {
                    Text("SAFELIST")
                        .font(.caption2.weight(.bold))
                        .tracking(0.06)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
