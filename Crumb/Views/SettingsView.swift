import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var whitelist: WhitelistModel
    @EnvironmentObject private var settings: SettingsStore
    @State private var newDomain = ""
    @State private var agentStatusChecked = false
    @State private var agentInstalled = false
    @State private var auditEntries: [AuditEntry] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                whitelistSection
                aiSection
                autoCleanSection
                agentSection
                auditSection
                logSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .onAppear {
            agentInstalled = LaunchAgentManager.isInstalled()
            agentStatusChecked = true
            auditEntries = AuditLog.allEntries(limit: 15)
            Task { await settings.refreshOllamaStatus() }
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

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "AI-classificatie (lokaal via Ollama)")
            Toggle("AI-classificatie gebruiken voor twijfelgevallen", isOn: $settings.ollamaEnabled)

            HStack {
                Text("Model")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("llama3.1:8b", text: $settings.ollamaModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button("Status controleren") {
                    Task { await settings.refreshOllamaStatus() }
                }
                .controlSize(.small)
            }

            Text(settings.ollamaStatusMessage.isEmpty
                 ? "Status nog niet gecontroleerd."
                 : settings.ollamaStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Het LLM ziet alleen metadata (domein, naam, vlaggen) — nooit cookie-waarden. Safelist-cookies worden nooit naar het model gestuurd. Zonder Ollama draait alles op de regellaag.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var autoCleanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Automatische schoonmaak (opt-in)")
            Toggle("Auto-clean inschakelen", isOn: $settings.autoCleanEnabled)

            Toggle("Marketing/tracking-cookies opruimen", isOn: $settings.autoCleanMarketingTracking)
                .disabled(!settings.autoCleanEnabled)
            Toggle("Analytics-cookies opruimen", isOn: $settings.autoCleanAnalytics)
                .disabled(!settings.autoCleanEnabled)

            HStack {
                Text("Minimale leeftijd")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Stepper("\(settings.autoCleanMinAgeDays) dagen", value: $settings.autoCleanMinAgeDays, in: 1...365)
                    .disabled(!settings.autoCleanEnabled)
            }

            Text("Alleen cookies die door zowel de regellaag als de AI als 'opschoonbaar' zijn gemarkeerd, de safelist niet raken én ouder zijn dan de ingestelde leeftijd komen in aanmerking. Elke verwijdering wordt gelogd in het audit-log. Browsers moeten gesloten zijn tijdens verwijdering.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Achtergrond-agent (launchd)")
            Text("Installeert een LaunchAgent die bij het inloggen start en daarna elke 3 uur een scan + rapport uitvoert (RunAtLoad + StartInterval 10800).")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                if agentInstalled {
                    Text("Geïnstalleerd")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button("Uitschakelen") {
                        LaunchAgentManager.uninstall()
                        agentInstalled = LaunchAgentManager.isInstalled()
                    }
                } else {
                    Text("Niet geïnstalleerd")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Installeren en inschakelen") {
                        try? LaunchAgentManager.install()
                        agentInstalled = LaunchAgentManager.isInstalled()
                    }
                }
            }

            Text("Logbestand: \(LaunchAgentManager.agentLogURL.path)")
                .font(.caption)
                .monospaced()
                .textSelection(.enabled)
        }
    }

    private var auditSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Audit-log (verwijderingen)")
            if auditEntries.isEmpty {
                Text("Nog geen verwijderingen uitgevoerd.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(auditEntries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(entry.mode.uppercased()) · \(entry.browser) · \(entry.domain)")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text(entry.timestamp.runTimestamp)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(entry.result.uppercased())
                                .font(.caption2.weight(.semibold))
                        }
                        Text("\(entry.name) — \(entry.detail ?? "")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Rapporten")
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
                Button("Verwijder rapporten ouder dan 90 dagen") {
                    _ = try? JSONRunLog.deleteLogs(olderThan: 90 * 24 * 60 * 60)
                }
                .help("Opruiming is een expliciete handmatige actie.")
            }
        }
    }

    private func addDomain() {
        whitelist.add(newDomain)
        newDomain = ""
    }
}
