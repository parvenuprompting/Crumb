import SwiftUI

@main
struct CrumbApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var scanService = ScanService.shared
    @StateObject private var whitelist = WhitelistModel()
    @ObservedObject private var settings = SettingsStore.shared
    @StateObject private var history = RunHistoryModel()

    var body: some Scene {
        MenuBarExtra("Crumb", systemImage: "circle.dotted") {
            MenuPanelView()
                .environmentObject(scanService)
                .environmentObject(whitelist)
                .environmentObject(settings)
                .environmentObject(history)
                .tint(.primary)
        }
        .menuBarExtraStyle(.window)

        Window("Crumb", id: "main") {
            MainContentView()
                .frame(minWidth: 860, minHeight: 580)
                .environmentObject(scanService)
                .environmentObject(whitelist)
                .environmentObject(settings)
                .environmentObject(history)
                .tint(.primary)
        }
        .defaultSize(width: 960, height: 640)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task { @MainActor in
            await ScanService.shared.runScan()
        }
    }
}

@MainActor
final class WhitelistModel: ObservableObject {
    @Published private(set) var domains: [String] = []

    init() {
        reload()
    }

    func reload() {
        domains = WhitelistStore.load().domains
            .map(WhitelistStore.normalizedDomain)
            .filter { !$0.isEmpty }
            .sorted()
    }

    func add(_ input: String) {
        let domain = WhitelistStore.normalizedDomain(input)
        guard !domain.isEmpty, !domains.contains(domain) else { return }
        var store = WhitelistStore.load()
        store.domains.append(domain)
        try? store.save()
        reload()
    }

    func remove(_ domain: String) {
        var store = WhitelistStore.load()
        store.domains.removeAll { WhitelistStore.normalizedDomain($0) == domain }
        try? store.save()
        reload()
    }
}
