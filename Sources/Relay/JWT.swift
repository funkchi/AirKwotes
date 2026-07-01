import Foundation

/// Decodes JWT payload claims (no signature verification).
enum JWT {
    static func payload(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        var s = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        guard let data = Data(base64Encoded: s) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static let authClaim = "https://api.openai.com/auth"

    static func expiry(of token: String) -> Date? {
        guard let p = payload(of: token), let exp = p["exp"] else { return nil }
        if let n = exp as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        if let d = exp as? Double { return Date(timeIntervalSince1970: d) }
        if let i = exp as? Int { return Date(timeIntervalSince1970: TimeInterval(i)) }
        return nil
    }

    static func email(of token: String) -> String? {
        if let e = payload(of: token)?["email"] as? String { return e }
        let profile = payload(of: token)?["https://api.openai.com/profile"] as? [String: Any]
        return profile?["email"] as? String
    }

    static func accountID(of token: String) -> String? {
        guard let p = payload(of: token) else { return nil }
        if let auth = p[authClaim] as? [String: Any] {
            return (auth["chatgpt_account_id"] as? String) ?? (auth["account_id"] as? String)
        }
        return p["chatgpt_account_id"] as? String ?? p["account_id"] as? String
    }

    static func planType(of token: String) -> String? {
        (payload(of: token)?[authClaim] as? [String: Any])?["chatgpt_plan_type"] as? String
    }
}
