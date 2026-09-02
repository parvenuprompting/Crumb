import SwiftUI

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
                                Text(ProtectionExplanation.explain(record))
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
