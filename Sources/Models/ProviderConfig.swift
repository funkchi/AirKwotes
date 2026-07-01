import Foundation

struct ProviderConfig: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var kind: ProviderKind
    var label: String
    var enabled: Bool

    init(id: UUID = UUID(), kind: ProviderKind, label: String? = nil, enabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.label = label?.isEmpty == false ? label! : kind.displayName
        self.enabled = enabled
    }
}
