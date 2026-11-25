import SwiftUI
import AppKit

/// "Sporen" — wat er over je naam te vinden is, en wat je eraan kunt doen.
/// De app zoekt niet zelf: hij bouwt de link, jij opent hem, en Crumb houdt
/// bij wat je vond en welke brief je verstuurde.
struct SporenView: View {
    @AppStorage("sporen.naam") private var naam = ""
    @AppStorage("sporen.plaats") private var plaats = ""
    @State private var entries: [ExposureEntry] = []
    @State private var brief: BriefToon?
    @State private var toonSync = false

    private var bestand: URL? { ExposureLedger.standaardBestand() }
    private var bronnen: [ExposureSource] { ExposureCatalog.bronnen }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if naam.trimmingCharacters(in: .whitespaces).isEmpty {
                leeg
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        bronnenLijst
                        administratie
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .padding()
        .task { laad() }
        .sheet(item: $brief) { inhoud in
            BriefSheet(brief: inhoud)
        }
        .sheet(isPresented: $toonSync) {
            SporenSyncSheet(bestand: bestand) { laad() }
        }
    }

    // MARK: - kop

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sporen")
                .font(.largeTitle.bold())
            Text("Wat er over je naam te vinden is — en de brief om het te laten verwijderen.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                TextField("Je naam", text: $naam)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                TextField("Woonplaats (optioneel)", text: $plaats)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Spacer()
                if !entries.isEmpty {
                    Text("\(entries.count) spoor(en) · \(openstaand) open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Synchroniseer") { toonSync = true }
                    .buttonStyle(.bordered)
                    .help("Maak je lijst gelijk met het huis op je telefoon")
            }
            .padding(.top, 4)
        }
    }

    private var leeg: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()
            Text("Vul je naam in.")
                .font(.title3)
            Text("Crumb bouwt dan per bron de zoeklink met jouw naam erin. Je opent hem zelf — er gaat niets naar een server die niet van jou is.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - bronnen

    private var bronnenLijst: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nulmeting")
                .font(.headline)
            ForEach(ExposureCategory.allCases, id: \.self) { categorie in
                let groep = bronnen.filter { $0.categorie == categorie }
                if !groep.isEmpty {
                    Text(categorie.titel.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(groep) { bron in
                        BronRij(bron: bron,
                                url: bron.url(naam: naam, plaats: plaats),
                                gevonden: entries.contains { $0.sourceID == bron.id },
                                onOpen: { open(bron) },
                                onMarkeer: { markeer(bron) })
                    }
                }
            }
        }
    }

    // MARK: - administratie

    private var administratie: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wat je vond")
                .font(.headline)
            if entries.isEmpty {
                Text("Nog niets gemarkeerd. Open een bron hierboven en markeer wat er over je staat.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.sourceNaam).font(.callout.weight(.medium))
                            Text("termijn tot \(entry.deadline.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(entry.deadline < Date() && entry.status != .verwijderd ? .red : .secondary)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { entry.status },
                            set: { zetStatus(entry, $0) }
                        )) {
                            ForEach(ExposureStatus.allCases, id: \.self) { status in
                                Text(status.titel).tag(status)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)

                        Button("Brief") { maakBrief(voor: entry) }
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
            if !entries.isEmpty {
                HStack {
                    Button("Kopieer de hele nulmeting") { kopieerAlles() }
                        .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    private var openstaand: Int {
        entries.filter { $0.status != .verwijderd }.count
    }

    // MARK: - acties

    private func open(_ bron: ExposureSource) {
        guard let url = bron.url(naam: naam, plaats: plaats) else { return }
        NSWorkspace.shared.open(url)
    }

    private func markeer(_ bron: ExposureSource) {
        guard let url = bron.url(naam: naam, plaats: plaats) else { return }
        let verzoek = RemovalRequest(soort: .verwijdering, ontvanger: bron.naam,
                                     naam: naam, gegevens: "naam en openbare vermelding")
        let boek = ExposureLedger(bestand: bestand)
        try? boek.laad()
        boek.voegToe(ExposureEntry(sourceID: bron.id, sourceNaam: bron.naam,
                                   url: url.absoluteString,
                                   deadline: verzoek.deadline,
                                   notitie: "gevonden op \(Date().formatted(date: .numeric, time: .omitted))"))
        try? boek.bewaar()
        laad()
    }

    private func zetStatus(_ entry: ExposureEntry, _ status: ExposureStatus) {
        let boek = ExposureLedger(bestand: bestand)
        try? boek.laad()
        boek.zetStatus(id: entry.id, status)
        try? boek.bewaar()
        laad()
    }

    private func maakBrief(voor entry: ExposureEntry) {
        let bron = ExposureCatalog.bron(id: entry.sourceID)
        let verzoek = RemovalRequest(soort: .verwijdering,
                                     ontvanger: bron?.naam ?? entry.sourceNaam,
                                     naam: naam,
                                     gegevens: entry.notitie.isEmpty
                                        ? "de vermelding op \(entry.url)"
                                        : "de vermelding op \(entry.url) (\(entry.notitie))")
        brief = BriefToon(titel: "Verwijderverzoek — \(entry.sourceNaam)", tekst: verzoek.tekst())
    }

    private func kopieerAlles() {
        var regels = ["Nulmeting sporen — \(naam)", ""]
        for entry in entries {
            regels.append("• \(entry.sourceNaam): \(entry.url)")
            regels.append("   status: \(entry.status.titel) · termijn: \(entry.deadline.formatted(date: .numeric, time: .omitted))")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(regels.joined(separator: "\n"), forType: .string)
    }

    private func laad() {
        let boek = ExposureLedger(bestand: bestand)
        try? boek.laad()
        entries = boek.entries.sorted { $0.gevondenOp > $1.gevondenOp }
    }
}

// MARK: - rij per bron

private struct BronRij: View {
    let bron: ExposureSource
    let url: URL?
    let gevonden: Bool
    let onOpen: () -> Void
    let onMarkeer: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: gevonden ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(gevonden ? Color.accentColor : Color.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(bron.naam).font(.callout.weight(.medium))
                Text(bron.uitleg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(bron.verwijderRoute)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(spacing: 6) {
                Button("Open") { onOpen() }
                    .buttonStyle(.bordered)
                    .disabled(url == nil)
                Button(gevonden ? "Gemarkeerd" : "Markeer") { onMarkeer() }
                    .buttonStyle(.borderedProminent)
                    .disabled(url == nil || gevonden)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - brief

private struct BriefToon: Identifiable {
    let id = UUID()
    let titel: String
    let tekst: String
}

private struct BriefSheet: View {
    let brief: BriefToon
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(brief.titel).font(.title3.bold())
            Text("Kopieer de tekst, plak hem in een e-mail en verstuur hem zelf. Crumb verstuurt niets.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: .constant(brief.tekst))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 560, minHeight: 380)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Button("Kopieer") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(brief.tekst, forType: .string)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("Sluiten") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(minWidth: 600)
    }
}
