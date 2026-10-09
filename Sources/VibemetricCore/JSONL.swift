import Foundation

enum JSONL {
    /// Parses each line of a JSONL file into a dictionary, skipping malformed lines.
    static func objects(at url: URL) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        var out: [[String: Any]] = []
        var start = data.startIndex
        let newline = UInt8(ascii: "\n")
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: newline) ?? data.endIndex
            if end > start,
               let obj = try? JSONSerialization.jsonObject(with: data[start..<end]) as? [String: Any] {
                out.append(obj)
            }
            start = end == data.endIndex ? end : data.index(after: end)
        }
        return out
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return isoFractional.date(from: s) ?? iso.date(from: s)
    }
}

extension String {
    /// Collapses whitespace and truncates to `limit` characters with an ellipsis.
    func clipped(_ limit: Int) -> String {
        let flat = split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}

/// Removes obvious secrets before any text is written to the evidence pack.
enum Redactor {
    private static let patterns: [NSRegularExpression] = [
        #"sk-[A-Za-z0-9_\-]{16,}"#,
        #"(ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]{16,}"#,
        #"AKIA[0-9A-Z]{16}"#,
        #"xox[abposr]-[A-Za-z0-9\-]{10,}"#,
        #"AIza[0-9A-Za-z_\-]{30,}"#,
        #"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
        #"(?i)(password|passwd|secret|api[_-]?key|token|authorization)(\s*[:=]\s*|\s+bearer\s+)["']?[^\s"',;]{6,}"#,
        #"(?i)(postgres|postgresql|mysql|mongodb(\+srv)?|redis|amqp)://[^\s"']+"#,
        #"https://hooks\.slack\.com/[^\s"')]+"#,
        #"https://(discord(app)?\.com)/api/webhooks/[^\s"')]+"#,
        #"(?i)([?&](key|token|sig|signature|access_token|api_key|apikey|secret)=)[^\s&"')]+"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static func scrub(_ text: String) -> String {
        var s = text
        for p in patterns {
            s = p.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "[REDACTED]")
        }
        return s
    }
}
