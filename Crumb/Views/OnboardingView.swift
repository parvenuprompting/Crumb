import SwiftUI

/// Korte onboarding bij de eerste start: privacybelofte, browserdetectie,
/// Volledige Schijftoegang, optionele lokale AI, eerste scan.
struct OnboardingView: View {
    @EnvironmentObject private var scanService: ScanService
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0

    private let totalSteps = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Welkom bij Crumb")
                    .font(.title.weight(.semibold))
                Spacer()
                Text("Stap \(step + 1) van \(totalSteps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch step {
            case 0: privacyStep
            case 1: browsersStep
            case 2: aiStep
            default: finishStep
            }

            Spacer()

            HStack {
                if step > 0 {
                    Button("Vorige") { step -= 1 }
                }
                Spacer()
                if step < totalSteps - 1 {
                    Button("Volgende") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Eerste scan uitvoeren") { finish() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 440)
    }

    // MARK: Stap 1 — privacy

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("Cookie-waarden worden niet gelezen of naar AI gestuurd. Alleen lokale metadata wordt gebruikt.")
                    .font(.callout.weight(.semibold))
            } icon: {
                Image(systemName: "lock.shield")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

            Text("Wat Crumb doet:")
                .font(.callout.weight(.semibold))
            bullet("Leest cookie-metadata (domein, naam, vlaggen) uit je browsers")
            bullet("Classificeert lokaal via regels en eventueel je eigen Ollama-model")
            bullet("Adviseert wat veilig opschoonbaar is — en verwijdert nooit zonder jouw bevestiging")
            bullet("Login- en sessie-cookies zijn altijd vergrendeld via de safelist")

            Text("Wat Crumb nooit doet:")
                .font(.callout.weight(.semibold))
            bullet("Waarden van cookies lezen, ontsleutelen of versturen")
            bullet("Automatisch verwijderen zonder uitgezet auto-clean én unanieme goedkeuring")
        }
    }

    // MARK: Stap 2 — browsers

    private var browsersStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Crumb heeft de volgende browsers gevonden:")
                .font(.callout)

            ForEach(scanService.sourceAvailability) { source in
                HStack {
                    Image(systemName: statusIcon(source))
                        .foregroundStyle(statusColor(source))
                    Text(source.browser)
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text(statusText(source))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if scanService.sourceAvailability.contains(where: \.requiresFullDiskAccess) {
                Text("Voor Safari is Volledige Schijftoegang nodig. Geef Crumb toegang in Systeeminstellingen → Privacy & Beveiliging → Volledige Schijftoegang en herstart daarna Crumb. Je kunt Crumb ook gewoon zonder Safari gebruiken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Systeeminstellingen openen") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }

            Text("Safari-cookies zijn read-only: Crumb verwijdert alleen in Chrome, Brave en Firefox.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Stap 3 — AI

    private var aiStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Lokale AI-classificatie gebruiken (optioneel)", isOn: $settings.ollamaEnabled)

            Text("Crumb kan twijfelgevallen laten beoordelen door een lokaal Ollama-model. Alles blijft op je Mac — het model ziet alleen domein, naam en vlaggen, nooit cookie-waarden.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Text("Model")
                    .foregroundStyle(.secondary)
                TextField("llama3.1:8b", text: $settings.ollamaModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }

            Text(settings.ollamaStatusMessage.isEmpty
                 ? "Zonder Ollama werkt Crumb ook — dan komt elk advies alleen uit de regellaag."
                 : settings.ollamaStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Installeer Ollama via ollama.com en trek een model met 'ollama pull llama3.1:8b'.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Stap 4 — klaar

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Alles staat klaar.")
                .font(.callout.weight(.semibold))

            bullet("Auto-clean staat bewust uit — je bepaalt alles handmatig tot je het zelf inschakelt in Instellingen")
            bullet("Elke verwijdering wordt eerst geback-upt en gelogd")
            bullet("Na de eerste scan zie je een overzicht met aanbevelingen")

            Text("De eerste scan leest nu de cookie-stores van je browsers. Dit duurt meestal enkele seconden.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
        }
    }

    private func statusIcon(_ source: ScanService.SourceAvailability) -> String {
        if !source.isInstalled { return "minus.circle" }
        if source.requiresFullDiskAccess { return "lock" }
        return "checkmark.circle"
    }

    private func statusColor(_ source: ScanService.SourceAvailability) -> Color {
        if !source.isInstalled { return .secondary }
        if source.requiresFullDiskAccess { return CookieVerdict.reviewSuggested.semanticColor }
        return CookieVerdict.safeToClean.semanticColor
    }

    private func statusText(_ source: ScanService.SourceAvailability) -> String {
        if !source.isInstalled { return "niet geïnstalleerd" }
        if source.requiresFullDiskAccess { return "Volledige Schijftoegang vereist" }
        return "gevonden"
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        dismiss()
        Task { await scanService.runScan() }
    }
}
