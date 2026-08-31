import SwiftUI

struct CookieListView: View {
    @EnvironmentObject private var scanService: ScanService
    @State private var searchText = ""
    @State private var browserFilter = "Alle"
    @State private var categoryFilter = "Alle"
    @State private var verdictFilter = "Alle"

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
            HStack(spacing: 10) {
                Picker("", selection: $browserFilter) {
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
            }

            if filtered.isEmpty {
                Text(scanService.lastRun == nil
                     ? "Nog geen scan uitgevoerd."
                     : "Geen cookies matchen de filters.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(filtered) { record in
                    CookieRow(record: record)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Zoek op domein of naam")
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
