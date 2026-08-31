import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var ollamaEnabled: Bool {
        didSet { defaults.set(ollamaEnabled, forKey: "ollamaEnabled") }
    }
    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: "ollamaModel") }
    }
    @Published var ollamaReachable: Bool
    @Published var ollamaStatusMessage: String = ""

    @Published var autoCleanEnabled: Bool {
        didSet { defaults.set(autoCleanEnabled, forKey: "autoCleanEnabled") }
    }
    @Published var autoCleanMarketingTracking: Bool {
        didSet { defaults.set(autoCleanMarketingTracking, forKey: "autoCleanMarketingTracking") }
    }
    @Published var autoCleanAnalytics: Bool {
        didSet { defaults.set(autoCleanAnalytics, forKey: "autoCleanAnalytics") }
    }
    @Published var autoCleanMinAgeDays: Int {
        didSet { defaults.set(autoCleanMinAgeDays, forKey: "autoCleanMinAgeDays") }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ollamaEnabled = defaults.bool(forKey: "ollamaEnabled")
        ollamaModel = defaults.string(forKey: "ollamaModel") ?? "llama3.1:8b"
        ollamaReachable = false
        autoCleanEnabled = defaults.bool(forKey: "autoCleanEnabled")
        autoCleanMarketingTracking = defaults.bool(forKey: "autoCleanMarketingTracking")
        autoCleanAnalytics = defaults.bool(forKey: "autoCleanAnalytics")
        autoCleanMinAgeDays = defaults.object(forKey: "autoCleanMinAgeDays") as? Int ?? 30
    }

    func refreshOllamaStatus() async {
        let client = OllamaClient()
        do {
            let models = try await client.listModels()
            ollamaReachable = true
            let short = ollamaModel.contains(":") ? ollamaModel : ollamaModel + ":latest"
            let present = models.contains(ollamaModel) || models.contains(short) || models.contains { $0.hasPrefix(ollamaModel) }
            ollamaStatusMessage = present
                ? "Draait — model '\(ollamaModel)' aanwezig."
                : "Draait — model '\(ollamaModel)' ontbreekt."
        } catch {
            ollamaReachable = false
            ollamaStatusMessage = error.localizedDescription
        }
    }
}
