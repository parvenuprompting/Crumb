import SwiftUI

enum CookieSortMode: String, CaseIterable, Identifiable {
    case domain = "Domein"
    case category = "Categorie"
    case firstSeen = "Eerst gezien"
    case age = "Ouderdom"
    case churn = "Churn"

    var id: String { rawValue }
}

struct CookieListView: View {
    @EnvironmentObject private var scanService: ScanService
    @EnvironmentObject private var whitelist: WhitelistModel
    @State private var searchText = ""
    @State private var browserFilter = "Alle"
    @State private var categoryFilter = "Alle"
    @State private var verdictFilter = "Alle"
    @State private var protectionFilter = "Alle"
    @State private var sortMode: CookieSortMode = .domain
    @State private var selection = Set<String>()
    @State private var detailRecord: CookieRecord?
    @State private var pendingDeleteTargets: [CookieRecord] = []
    @State private var showDeleteConfirmation = false
    @State private var deleteResults: [DeletionResult]?
    @State private var isDeleting = false
    @State private var notice: String?

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
            switch protectionFilter {
            case "Vergrendeld": if !record.protection.isLocked { return false }
            case "Review-only": if !record.protection.isReviewOnly { return false }
            case "Geen bescherming": if record.protection != .none { return false }
            default: break
            }
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
            switch sortMode {
            case .domain:
                if a.domain != b.domain { return a.domain < b.domain }
                return a.name < b.name
            case .category:
                if a.category != b.category { return a.category.rawValue < b.category.rawValue }
                if a.domain != b.domain { return a.domain < b.domain }
                return a.name < b.name
            case .firstSeen:
                return a.firstSeen < b.firstSeen
            case .age:
                return a.firstSeen < b.firstSeen
            case .churn:
                return (a.valueChurn ?? 0) > (b.valueChurn ?? 0)
            }
        }
    }

    private var activeFilterCount: Int {
        [browserFilter, categoryFilter, verdictFilter, protectionFilter]
            .filter { $0 != "Alle" }.count + (searchText.isEmpty ? 0 : 1)
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 8) {
                filterBar
                if activeFilterCount > 0 {
                    filterChips
                }
                if filtered.isEmpty {
                    emptyState
                } else {
                    cookieList
                }
                if let notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Zoek op domein of naam")
        } detail: {
            if let detailRecord {
                CookieDetailView(
                    record: detailRecord,
                    allRecords: records,
                    onWhitelistDomain: { domain in
                        showNotice(whitelist.add(domain) ?? "'\(domain)' staat op de whitelist — beschermd na de volgende scan.")
                    },
                    onProtectToggle: { record in
                        toggleProtection(record)
                    },
                    onDelete: { record in
                        pendingDeleteTargets = [record]
                        deleteResults = nil
                        showDeleteConfirmation = true
                    },
                    onSelectSimilar: { other in
                        self.detailRecord = other
                    }
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.right")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Selecteer een cookie voor details")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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

    private var filterBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $browserFilter) {
                Text("Alle").tag("Alle")
                ForEach(availableBrowsers, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 100)

            Picker("", selection: $categoryFilter) {
                Text("Alle").tag("Alle")
                ForEach(CookieCategory.allCases, id: \.self) { category in
                    Text(category.displayName).tag(category.displayName)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            Picker("", selection: $verdictFilter) {
                Text("Alle").tag("Alle")
                ForEach(CookieVerdict.allCases, id: \.self) { verdict in
                    Text(verdict.displayName).tag(verdict.displayName)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            Picker("", selection: $protectionFilter) {
                Text("Alle").tag("Alle")
                Text("Vergrendeld").tag("Vergrendeld")
                Text("Review-only").tag("Review-only")
                Text("Geen bescherming").tag("Geen bescherming")
            }
            .labelsHidden()
            .frame(width: 150)

            Picker("", selection: $sortMode) {
                ForEach(CookieSortMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 120)
        }
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            if browserFilter != "Alle" { chip(browserFilter) { browserFilter = "Alle" } }
            if categoryFilter != "Alle" { chip(categoryFilter) { categoryFilter = "Alle" } }
            if verdictFilter != "Alle" { chip(verdictFilter) { verdictFilter = "Alle" } }
            if protectionFilter != "Alle" { chip(protectionFilter) { protectionFilter = "Alle" } }
            if !searchText.isEmpty { chip("'\(searchText)'") { searchText = "" } }

            Button("Wis filters") {
                browserFilter = "Alle"
                categoryFilter = "Alle"
                verdictFilter = "Alle"
                protectionFilter = "Alle"
                searchText = ""
            }
            .buttonStyle(.plain)
            .underline()
            .controlSize(.small)
            Spacer()
        }
    }

    private func chip(_ label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private var emptyState: some View {
        Text(scanService.lastRun == nil
             ? "Nog geen scan uitgevoerd."
             : "Geen cookies matchen de filters.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var cookieList: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Spacer()
                if !selection.isEmpty {
                    Text("\(selection.count) geselecteerd")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Button("Whitelist domeinen") {
                        whitelistSelectedDomains()
                    }
                    .controlSize(.small)
                }
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

            List(selection: $selection) {
                ForEach(filtered) { record in
                    CookieRow(record: record)
                        .tag(record.id)
                        .contextMenu {
                            Button("Toon details") { detailRecord = record }
                            Button("Verwijderen…") {
                                pendingDeleteTargets = [record]
                                deleteResults = nil
                                showDeleteConfirmation = true
                            }
                            .disabled(record.protection.isLocked)
                            Button("Voeg '\(record.domain)' toe aan whitelist") {
                                if let message = whitelist.add(record.domain) {
                                    showNotice(message)
                                } else {
                                    showNotice("'\(record.domain)' staat op de whitelist — beschermd na de volgende scan.")
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            detailRecord = record
                        }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func whitelistSelectedDomains() {
        let domains = Set(filtered.filter { selection.contains($0.id) }.map(\.domain))
        var added = 0
        for domain in domains where whitelist.add(domain) == nil {
            added += 1
        }
        showNotice("\(added) van \(domains.count) domeinen toegevoegd aan de whitelist.")
    }

    private func toggleProtection(_ record: CookieRecord) {
        var store = ProtectedCookieStore.load()
        if store.contains(domain: record.domain, name: record.name, path: record.path) {
            store.remove(domain: record.domain, name: record.name, path: record.path)
            showNotice("Bescherming opgeheven — beschermd-status verdwijnt na de volgende scan.")
        } else {
            store.add(domain: record.domain, name: record.name, path: record.path)
            showNotice("Cookie handmatig beschermd — actief na de volgende scan.")
        }
        try? store.save()
        Task { await scanService.runScan() }
    }

    private func showNotice(_ message: String) {
        notice = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if notice == message { notice = nil }
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

struct CookieRow: View {
    let record: CookieRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(record.domain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()

                if record.protection.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Beschermd door safelist")
                } else if record.protection.isReviewOnly {
                    Image(systemName: "eye")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Review-only: mogelijk actieve sessie")
                }

                Label(record.verdict.displayName, systemImage: record.verdict.systemImage)
                    .font(.caption2.weight(Mono.verdictWeight(record.verdict)))
                    .foregroundStyle(record.verdict.semanticColor)
            }

            HStack(spacing: 10) {
                Text(record.browser)
                if let churn = record.valueChurn, churn > 0 {
                    Label("\(churn)× ververst", systemImage: "arrow.clockwise")
                }
                if record.isSecure { Text("secure") }
                if record.isHttpOnly { Text("httpOnly") }
                if record.isSessionOnly {
                    Text("sessie")
                } else if let expiry = record.expiry {
                    Text("vervalt \(expiry.formatted(date: .numeric, time: .omitted))")
                }
                Text("eerst gezien \(record.firstSeen.ageDescription)")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
