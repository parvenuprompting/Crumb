import Foundation
import Combine

@MainActor
final class RunHistoryModel: ObservableObject {
    @Published private(set) var runs: [ScanRun] = []

    func reload() {
        runs = JSONRunLog.allRuns(limit: 30).reversed()
    }
}

struct TrendPoint: Identifiable {
    let date: Date
    let tracking: Int
    let review: Int
    let total: Int

    var id: Date { date }
}
