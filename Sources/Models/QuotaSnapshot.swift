import Foundation

struct QuotaSnapshot: Identifiable, Equatable {
    let id: UUID
    var remainingPercent: Double?
    var remainingDisplay: String
    var usedDisplay: String?
    var totalDisplay: String?
    var unit: String
    var status: Status
    var fetchedAt: Date?
    var resetAt: Date?
    var note: String?

    // Optional secondary window (e.g. Codex weekly plan, GLM MCP monthly).
    var secondaryRemainingPercent: Double? = nil
    var secondaryLabel: String? = nil

    enum Status: Equatable {
        case ok, low, critical, invalid, unsupported, loading, error(String)
    }

    static let empty = QuotaSnapshot(
        id: UUID(), remainingPercent: nil, remainingDisplay: "—",
        usedDisplay: nil, totalDisplay: nil, unit: "", status: .loading,
        fetchedAt: nil, resetAt: nil, note: nil)

    static func == (lhs: QuotaSnapshot, rhs: QuotaSnapshot) -> Bool { lhs.id == rhs.id }
}

extension QuotaSnapshot.Status {
    var isProblem: Bool {
        switch self {
        case .invalid, .unsupported, .error: return true
        default: return false
        }
    }
    /// Transient problems worth suppressing until they repeat (network blips, 401s).
    var isTransientFailure: Bool {
        switch self {
        case .invalid, .error: return true
        default: return false
        }
    }
}
