import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var whitelist: WhitelistModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var scanService: ScanService
    @State private var newDomain = ""
    @State private var whitelistNotice: String?
    @State private var agentInstalled = false
    @State private var auditEntries: [AuditEntry] = []
    @State private var backups: [BackupMetadata] = []
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    // Domeinregels
    @State private var domainRules: [DomainRule] = []
    @State private var ruleDomain = ""
    @State private var ruleAction: DomainRule.Action = .alwaysKeep
    @State private var ruleCookieName = ""
    @State private var ruleBrowser = "Alle"
    @State private var ruleDays = 30

    // Audit-log filters
    @State private var auditSearch = ""
    @State private var auditBrowserFilter = "Alle"
    @State private var auditResultFilter = "Alle"

    private var auditBrowsers: [String] {
        Array(Set(auditEntries.map(\.browser))).sorted()
    }

    private var filteredAudit: [AuditEntry] {
        auditEntries.filter { entry in
            if auditBrowserFilter != "Alle", entry.browser != auditBrowserFilter { return false }
            if auditResultFilter != "Alle", entry.result != auditResultFilter { return false }
            if !auditSearch.isEmpty {
                let query = auditSearch.lowercased()
                if !entry.domain.lowercased().contains(query),
                   !entry.name.lowercased().contains(query),
                   !entry.mode.lowercased().contains(query) {
                    return false
                }
            }
            return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                statusSection
                whitelistSection
                domainRulesSection
                aiSection
                autoCleanSection
                agentSection
                backupsSection
                auditSection
                logSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .onAppear {
            agentInstalled = LaunchAgentManager.isInstalled()
            auditEntries = AuditLog.allEntries(limit: 200)
            backups = CookieBackupStore.listBackups(limit: 8)
            domainRules = DomainRulesStore.load().rules
            Task { await settings.refreshOllamaStatus() }
        }
    }

    // MARK: - Risico-indicatie

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Status")
            HStack(spacing: 16) {
                statusPill("Auto-clean", settings.autoCleanEnabled ? "aan (\(settings.autoCleanMinAgeDays)d+, max \(settings.autoCleanMaxPerRun)/run)" : "uit", active: settings.autoCleanEnabled)
                statusPill("AI", settings.ollamaEnabled ? (settings.ollamaReachable ? "lokaal actief" : "ingesteld, niet bereikbaar") : "uit", active: settings.ollamaEnabled && settings.ollamaReachable)
                statusPill("Back-ups", settings.backupRetentionDays == 0 ? "voor altijd" : "\(settings.backupRetentionDays) dagen", active: true)
                statusPill("Agent", agentInstalled ? "actief (\(settings.agentIntervalHours) uur)" : "uit", active: agentInstalled)
            }
        }
    }

    private func statusPill(_ title: String, _ value: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? CookieVerdict.safeToClean.semanticColor : Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
            Text("\(title): \(value)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
    }

    // MARK: - Whitelist

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

            if let whitelistNotice {
                Text(whitelistNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Exporteren…") { exportWhitelist() }
                Button("Importeren…") { importWhitelist() }
            }
            .controlSize(.small)

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

    // MARK: - Domeinregels

    private var domainRulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Domeinregels — fijnmaziger dan de whitelist")
            Text("Regels gelden bovenop de veiligheidslaag; beschermde cookies raken ze nooit. Voorbeeld: 'shop.example — opschonen ouder dan 30 dagen'.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("domein.nl", text: $ruleDomain)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Picker("", selection: $ruleAction) {
                    ForEach(DomainRule.Action.allCases) { action in
                        Text(action.rawValue).tag(action)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }
            HStack(spacing: 8) {
                TextField("cookienaam (optioneel)", text: $ruleCookieName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Picker("", selection: $ruleBrowser) {
                    Text("Alle browsers").tag("Alle")
                    ForEach(availableRuleBrowsers, id: \.self) { browser in
                        Text(browser).tag(browser)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                if ruleAction == .cleanupOlderThan {
                    Stepper("\(ruleDays) dagen", value: $ruleDays, in: 1...365)
                        .frame(width: 150)
                }
                Button("Regel toevoegen") { addRule() }
                    .disabled(ruleDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if domainRules.isEmpty {
                Text("Nog geen domeinregels.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(domainRules) { rule in
                    HStack {
                        Text(rule.summary)
                            .font(.callout)
                            .monospaced()
                        Spacer()
                        Button("Verwijderen") { removeRule(rule) }
                            .controlSize(.small)
                            .buttonStyle(.plain)
                            .underline()
                    }
                }
            }
        }
    }

    private var availableRuleBrowsers: [String] {
        Array(Set(scanService.lastRun?.records.map(\.browser) ?? [])).sorted()
    }

    private func addRule() {
        let domain = WhitelistStore.normalizedDomain(ruleDomain)
        guard WhitelistStore.isValidWhitelistDomain(domain) else { return }
        var rule = DomainRule(
            domain: domain,
            action: ruleAction,
            cookieName: ruleCookieName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : ruleCookieName.trimmingCharacters(in: .whitespaces),
            browser: ruleBrowser == "Alle" ? nil : ruleBrowser,
            olderThanDays: ruleAction == .cleanupOlderThan ? ruleDays : nil
        )
        if ruleAction != .protectCookieName && ruleAction != .deleteCookieName {
            rule.cookieName = nil
        }
        var store = DomainRulesStore.load()
        guard !store.rules.contains(where: { $0.id == rule.id }) else { return }
        store.rules.append(rule)
        try? store.save()
        domainRules = store.rules
        ruleDomain = ""
        ruleCookieName = ""
    }

    private func removeRule(_ rule: DomainRule) {
        var store = DomainRulesStore.load()
        store.rules.removeAll { $0.id == rule.id }
        try? store.save()
        domainRules = store.rules
    }

    // MARK: - AI

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

    // MARK: - Auto-clean

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

            HStack {
                Text("Maximaal per run")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Stepper("\(settings.autoCleanMaxPerRun) cookies", value: $settings.autoCleanMaxPerRun, in: 10...500, step: 10)
                    .disabled(!settings.autoCleanEnabled)
            }

            HStack {
                Text("Start pas bij")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Stepper("minstens \(settings.autoCleanMinSafeCookies) veilige cookies (0 = altijd)", value: $settings.autoCleanMinSafeCookies, in: 0...200, step: 10)
                    .disabled(!settings.autoCleanEnabled)
            }

            HStack {
                Button("Dry run — bekijk wat verwijderd zou worden") {
                    showDryRunPreview()
                }
                .disabled(!settings.autoCleanEnabled)
            }

            Text("Alleen cookies die door zowel de regellaag als de AI als 'opschoonbaar' zijn gemarkeerd, de safelist niet raken én ouder zijn dan de ingestelde leeftijd komen in aanmerking. Elke verwijdering wordt geback-upt en gelogd in het audit-log. Browsers moeten gesloten zijn tijdens verwijdering.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @State private var dryRunCandidates: [CookieRecord]?
    @State private var showDryRun = false

    private func showDryRunPreview() {
        let autoSettings = AutoCleanSettings(
            enabled: true,
            includeMarketingTracking: settings.autoCleanMarketingTracking,
            includeAnalytics: settings.autoCleanAnalytics,
            minAgeDays: settings.autoCleanMinAgeDays,
            maxPerRun: settings.autoCleanMaxPerRun,
            minSafeCookies: settings.autoCleanMinSafeCookies
        )
        guard let run = scanService.lastRun else { return }
        dryRunCandidates = AutoCleanEngine.candidates(in: run, settings: autoSettings)
        showDryRun = true
    }

    private var dryRunSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dry run — niets is verwijderd")
                .font(.headline)
            if let candidates = dryRunCandidates {
                if candidates.isEmpty {
                    Text("Momenteel geen cookies die aan de auto-cleanvoorwaarden voldoen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(candidates.count) cookie(s) zouden verwijderd worden:")
                        .font(.callout)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(candidates) { record in
                                Text("\(record.name) · \(record.domain) · \(record.browser) — \(record.reasoning)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            }
            HStack {
                Spacer()
                Button("Sluiten") { showDryRun = false }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    // MARK: - Agent

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Achtergrond-agent (launchd)")
            Text("Installeert een LaunchAgent die bij het inloggen start en met een instelbare frequentie een scan + (optioneel) auto-clean uitvoert.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Text("Frequentie")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("", selection: $settings.agentIntervalHours) {
                    Text("elk uur").tag(1)
                    Text("elke 3 uur").tag(3)
                    Text("elke 6 uur").tag(6)
                    Text("elke 12 uur").tag(12)
                }
                .labelsHidden()
                .frame(width: 140)
                .onChange(of: settings.agentIntervalHours) { _, newValue in
                    if agentInstalled {
                        try? LaunchAgentManager.reinstall(intervalHours: newValue)
                    }
                }
            }

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
                        try? LaunchAgentManager.install(intervalHours: settings.agentIntervalHours)
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

    // MARK: - Back-ups

    private var backupsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Back-ups (vóór verwijdering)")
            HStack {
                Text("Bewaartermijn")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("", selection: $settings.backupRetentionDays) {
                    Text("7 dagen").tag(7)
                    Text("30 dagen").tag(30)
                    Text("90 dagen").tag(90)
                    Text("365 dagen").tag(365)
                    Text("voor altijd").tag(0)
                }
                .labelsHidden()
                .frame(width: 140)
            }
            Text("Elke verwijderingsactie schrijft eerst een back-up weg; lukt dat niet, dan wordt er niet verwijderd. Back-ups bevatten cookie-waarden en blijven lokaal staan met alleen-lezenrechten voor de eigenaar.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if backups.isEmpty {
                Text("Nog geen back-ups.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(backups) { backup in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backup.createdAt.runTimestamp)
                                .font(.callout.weight(.medium))
                            Text("\(backup.entryCount) cookies")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Herstellen") { restoreBackup(backup) }
                            .controlSize(.small)
                            .disabled(isRestoring)
                    }
                    .padding(.vertical, 2)
                    Divider().opacity(0.4)
                }
            }

            if let restoreMessage {
                Text(restoreMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Verwijder oude back-ups nu") {
                    let interval = settings.backupRetentionDays == 0 ? 0 : TimeInterval(settings.backupRetentionDays) * 86_400
                    if interval > 0 {
                        _ = try? CookieBackupStore.deleteBackups(olderThan: interval)
                    }
                    backups = CookieBackupStore.listBackups(limit: 8)
                }
                Button("Open map") {
                    NSWorkspace.shared.open(CookieBackupStore.directory)
                }
            }
            .controlSize(.small)
        }
    }

    private func restoreBackup(_ backup: BackupMetadata) {
        isRestoring = true
        restoreMessage = nil
        Task { @MainActor in
            let outcome = await CookieBackupStore.restore(from: backup.url)
            isRestoring = false
            restoreMessage = "\(outcome.summary) — herstart de browser om de cookies te zien."
            backups = CookieBackupStore.listBackups(limit: 8)
        }
    }

    // MARK: - Audit-log

    private var auditSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Audit-log (verwijderingen)")
            HStack(spacing: 8) {
                TextField("Zoek in domein, naam of modus", text: $auditSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Picker("", selection: $auditBrowserFilter) {
                    Text("Alle browsers").tag("Alle")
                    ForEach(auditBrowsers, id: \.self) { browser in
                        Text(browser).tag(browser)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                Picker("", selection: $auditResultFilter) {
                    Text("Alle resultaten").tag("Alle")
                    Text("verwijderd").tag("deleted")
                    Text("mislukt").tag("failed")
                }
                .labelsHidden()
                .frame(width: 150)
                Spacer()
                Button("Exporteer CSV…") { exportAudit(csv: true) }
                Button("Exporteer JSON…") { exportAudit(csv: false) }
            }
            .controlSize(.small)

            let deleted = filteredAudit.filter { $0.result == "deleted" }.count
            let failed = filteredAudit.count - deleted
            Text("\(filteredAudit.count) acties · \(deleted) verwijderd · \(failed) mislukt/geblokkeerd")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if filteredAudit.isEmpty {
                Text("Nog geen verwijderingen uitgevoerd.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(filteredAudit.prefix(30).enumerated()), id: \.offset) { _, entry in
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

    private func exportAudit(csv: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [csv ? UTType.commaSeparatedText : UTType.json]
        panel.nameFieldStringValue = csv ? "crumb-audit.csv" : "crumb-audit.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if csv {
                try AuditLog.exportCSV(entries: filteredAudit, to: url)
            } else {
                try AuditLog.exportJSON(entries: filteredAudit, to: url)
            }
        } catch {
            // stil falen is hier acceptabel; het panel toont fouten al
        }
    }

    // MARK: - Rapporten

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

    // MARK: - Whitelist helpers

    private func addDomain() {
        if let error = whitelist.add(newDomain) {
            whitelistNotice = error
        } else {
            whitelistNotice = nil
            newDomain = ""
        }
    }

    private func exportWhitelist() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "crumb-whitelist.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try whitelist.export(to: url)
            whitelistNotice = "Whitelist geëxporteerd naar \(url.lastPathComponent)."
        } catch {
            whitelistNotice = "Exporteren mislukt: \(error.localizedDescription)"
        }
    }

    private func importWhitelist() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let added = try whitelist.importDomains(from: url)
            whitelistNotice = "\(added) domein(en) geïmporteerd."
        } catch {
            whitelistNotice = "Importeren mislukt: \(error.localizedDescription)"
        }
    }
}
