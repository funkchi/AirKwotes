import Foundation

enum Format {
    static func value(_ amount: Double, currency: String?) -> String {
        let n = NumberFormatter()
        n.maximumFractionDigits = 2
        n.minimumFractionDigits = 2
        n.numberStyle = .decimal
        let num = n.string(from: NSNumber(value: amount)) ?? "\(amount)"
        switch currency?.uppercased() {
        case "CNY", "RMB": return "¥\(num)"
        case "USD":        return "$\(num)"
        case "EUR":        return "€\(num)"
        case nil:          return num
        default:           return "\(num) \(currency!)"
        }
    }

    static func tokens(_ n: Double) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", n / 1_000) }
        return "\(Int(n))"
    }

    static func percent(_ p: Double) -> String {
        let v = Int((min(max(p, 0), 1)) * 100)
        return "\(v)%"
    }

    static func relativeTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func masked(_ key: String) -> String {
        let s = key.trimmingCharacters(in: .whitespaces)
        guard s.count > 8 else { return String(repeating: "•", count: max(s.count, 4)) }
        let head = s.prefix(4)
        let tail = s.suffix(4)
        return "\(head)••••\(tail)"
    }
}
