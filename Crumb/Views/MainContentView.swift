import SwiftUI

struct MainContentView: View {
    @EnvironmentObject private var scanService: ScanService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(0)
            CookieListView()
                .tabItem {
                    Label("Cookies", systemImage: "circle.grid.2x2")
                }
                .tag(1)
            TrendsView()
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)
            SettingsView()
                .tabItem {
                    Label("Instellingen", systemImage: "gearshape")
                }
                .tag(3)
        }
        .padding()
    }
}

struct MenuPanelView: View {
    @EnvironmentObject private var scanService: ScanService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Crumb")
                    .font(.headline)
                Spacer()
                if scanService.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let run = scanService.lastRun {
                Text("Laatste scan: \(run.finishedAt.runTimestamp)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let used = run.aiUsed, used {
                    Text("AI: \(run.aiClassifiedCount ?? 0) beoordeeld")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let reason = run.aiSkippedReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                StatRow(title: "Gescand", value: "\(run.records.count)", emphasized: true)
                StatRow(title: "Beschermd (safelist)", value: "\(run.lockedCount)")
                StatRow(title: "Review aanbevolen", value: "\(run.verdictCounts[.reviewSuggested, default: 0])", emphasized: true)
                StatRow(title: "Opschoonbaar", value: "\(run.verdictCounts[.safeToClean, default: 0])")
            } else if scanService.isScanning {
                Text("Eerste scan loopt…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nog geen scan uitgevoerd.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = scanService.lastError {
                Divider()
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Open Crumb") {
                openWindow(id: "main")
            }
            .frame(maxWidth: .infinity)

            Button("Scan nu") {
                Task { await scanService.runScan() }
            }
            .disabled(scanService.isScanning)
            .frame(maxWidth: .infinity)

            Button("Stop") {
                NSApp.terminate(nil)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(width: 260)
    }
}
