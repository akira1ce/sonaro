import Foundation

/// Parses both ordinary cookie strings and the QR endpoint's `;;` separators.
enum SessionCookie {
    static func fields(_ raw: String?) -> [String: String] {
        var result: [String: String] = [:]
        let attributes: Set<String> = ["path", "domain", "expires", "max-age", "samesite", "priority"]
        for part in (raw ?? "").split(separator: ";") {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let name = part[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !attributes.contains(name.lowercased()) else { continue }
            let value = part[part.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            result[name] = value
        }
        return result
    }

    static func hasLoginCredential(_ raw: String?) -> Bool {
        guard let token = fields(raw)["MUSIC_U"] else { return false }
        return !token.trimmingCharacters(in: CharacterSet(charactersIn: "\" ").union(.whitespacesAndNewlines)).isEmpty
    }
}
