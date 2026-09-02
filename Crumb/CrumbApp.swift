import SwiftUI

@main
struct CrumbApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var scanService = ScanService.shared
    @StateObject private var whitelist = WhitelistModel()
    @ObservedObject private var settings = SettingsStore.shared
    @StateObject private var history = RunHistoryModel()

    var body: some Scene {
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

        MenuBarExtra("Crumb", systemImage: "circle.dotted") {
            MenuPanelView()
                .environmentObject(scanService)
                .environmentObject(whitelist)
                .environmentObject(settings)
                .environmentObject(history)
                .tint(.primary)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        ScanService.shared.loadLastRunFromDisk()
        Task { @MainActor in
            await ScanService.shared.runScan()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.activate(ignoringOtherApps: true)
        if !flag {
            if let window = sender.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
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

    /// Voegt een domein toe na normalisatie. Geeft nil terug bij succes,
    /// anders een foutmelding voor de UI.
    @discardableResult
    func add(_ input: String) -> String? {
        let domain = WhitelistStore.normalizedDomain(input)
        guard WhitelistStore.isValidWhitelistDomain(domain) else {
            return "Voer een geldig domein in zoals 'bank.nl'."
        }
        guard !domains.contains(domain) else {
            return "'\(domain)' staat al op de whitelist."
        }
        var store = WhitelistStore.load()
        store.domains.append(domain)
        try? store.save()
        reload()
        return nil
    }

    func remove(_ domain: String) {
        var store = WhitelistStore.load()
        store.domains.removeAll { WhitelistStore.normalizedDomain($0) == domain }
        try? store.save()
        reload()
    }
}
