import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var whitelist: WhitelistModel
    @EnvironmentObject private var scanService: ScanService
    @State private var newDomain = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                whitelistSection
                logSection
                infoSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private var whitelistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Whitelist — nooit wissen")
            Text("Domeinen op deze lijst worden altijd beschermd, los van elk advies. Voer een domein in zoals 'bank.nl' — alle subdomeinen vallen eronder.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("domein.nl", text: $newDomain)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onSubmit(addDomain)
                Button("Toevoegen") { addDomain() }
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if whitelist.domains.isEmpty {
                Text("Nog geen domeinen op de whitelist.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(whitelist.domains, id: \.self) { domain in
                    HStack {
                        Text(domain)
                            .font(.callout.weight(.medium))
                            .monospaced()
                        Spacer()
                        Button("Verwijderen") { whitelist.remove(domain) }
                            .controlSize(.small)
                            .buttonStyle(.plain)
                            .underline()
                    }
                }
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Logs")
            Text("Elke run schrijft een JSON-rapport naar:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(JSONRunLog.logsDirectory.path)
                .font(.caption)
                .monospaced()
                .textSelection(.enabled)

            HStack {
                Button("Open logmap") {
                    NSWorkspace.shared.open(JSONRunLog.logsDirectory)
                }
                Button("Verwijder logs ouder dan 90 dagen") {
                    _ = try? JSONRunLog.deleteLogs(olderThan: 90 * 24 * 60 * 60)
                }
                .help("Opruiming is een expliciete handmatige actie.")
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Status")
            StatRow(title: "AI-classificatie (Ollama)", value: "nog niet actief — regellaag alleen")
            StatRow(title: "Automatische schoonmaak", value: "uit — verwijderen volgt in een latere versie")
            StatRow(title: "Achtergrond-agent (launchd)", value: "nog niet geïnstalleerd — scans via de app")
        }
    }

    private func addDomain() {
        whitelist.add(newDomain)
        newDomain = ""
    }
}
