import SwiftUI

/// Synchroniseren met het huis op de VPS. Het adres staat in de instellingen,
/// de sleutel in de sleutelhanger — nooit in een gewoon bestand.
struct SporenSyncSheet: View {
    let bestand: URL?
    let onKlaar: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("sporen.syncadres") private var adres = "https://ubuntu-4gb-fsn1-2.tail214c32.ts.net:7467"
    @State private var sleutel = ""
    @State private var bezig = false
    @State private var melding: String?
    @State private var fout: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Synchroniseer met je huis")
                .font(.title3.bold())
            Text("Wat je hier markeert, staat ook op je telefoon. Het huis voegt samen: per spoor wint de laatste wijziging. Je sleutel gaat naar de sleutelhanger.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Adres van je huis", text: $adres)
                .textFieldStyle(.roundedBorder)
            SecureField("Synchronisatiesleutel", text: $sleutel)
                .textFieldStyle(.roundedBorder)
            Text("De sleutel staat op de Sporen-pagina in je huis, onderaan bij \"Sleutel\".")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if let melding {
                Text(melding).font(.callout).foregroundStyle(.green)
            }
            if let fout {
                Text(fout).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Button(bezig ? "Bezig…" : "Synchroniseer") {
                    Task { await doen() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(bezig || sleutel.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()

                Button("Sluiten") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(minWidth: 520)
        .task {
            if sleutel.isEmpty { sleutel = Sleutelbewaarder.lees("syncsleutel") ?? "" }
        }
    }

    private func doen() async {
        bezig = true
        fout = nil
        melding = nil
        defer { bezig = false }

        let boek = ExposureLedger(bestand: bestand)
        try? boek.laad()
        let client = ExposureSyncClient(adres: adres,
                                        sleutel: sleutel.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            let vanHuis = try await client.synchroniseer(boek.entries.map(SpoorVertaling.record(van:)))
            let samengevoegd = vanHuis.compactMap(SpoorVertaling.entry(van:))
            boek.vervangAlles(samengevoegd)
            try boek.bewaar()
            Sleutelbewaarder.bewaar(sleutel, voor: "syncsleutel")
            melding = "\(samengevoegd.count) sporen — gelijk met het huis."
            onKlaar()
        } catch {
            fout = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
