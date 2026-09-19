import Foundation
import Combine

/// The free release allows successful exports of 50 new works per local ISO week.
enum ExportQuotaPolicy: Equatable {
    case weekly(limit: Int)

    static let current = Self.weekly(limit: 50)

    var limit: Int {
        switch self {
        case .weekly(let limit): max(0, limit)
        }
    }
}

/// Quotas apply to successfully exported captures, never previews or cancelled shares.
@MainActor
final class ExportQuotaStore: ObservableObject {
    @Published private var exports: [String: Date]

    private let defaults: UserDefaults
    let quotaPolicy: ExportQuotaPolicy
    private let calendar: Calendar
    private let currentDate: () -> Date
    // Preserve the ledger written by previous versions when the app is upgraded.
    private let quotaKey = "successfulCaptureExports.v1"

    init(defaults: UserDefaults = .standard, quotaPolicy: ExportQuotaPolicy = .current,
         calendar: Calendar = Calendar(identifier: .iso8601), currentDate: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.quotaPolicy = quotaPolicy
        self.calendar = calendar
        self.currentDate = currentDate
        exports = (defaults.dictionary(forKey: quotaKey) ?? [:]).compactMapValues { $0 as? Date }
    }

    var exportLimit: Int { quotaPolicy.limit }

    var remainingExports: Int {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: currentDate()) else { return 0 }
        let used = exports.values.filter { $0 >= interval.start && $0 < interval.end }.count
        return max(0, exportLimit - used)
    }

    func canExport(sessionID: UUID) -> Bool {
        exports[sessionID.uuidString] != nil || remainingExports > 0
    }

    func recordSuccessfulExport(sessionID: UUID) {
        guard exports[sessionID.uuidString] == nil else { return }
        exports[sessionID.uuidString] = currentDate()
        defaults.set(exports, forKey: quotaKey)
    }

    func recordShareCompletion(sessionID: UUID, completed: Bool) {
        guard completed else { return }
        recordSuccessfulExport(sessionID: sessionID)
    }
}
