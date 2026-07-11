import Foundation

/// A deterministic, local-only privacy filter. It intentionally redacts only
/// high-confidence categories; name/address detection is omitted until Aura
/// ships a separately verifiable on-device classifier.
struct PrivacyFilter {
    func inspect(_ text: String, settings: PrivacySettings) -> PrivacyReview? {
        var working = text
        var matches: [PrivacyMatch] = []
        var counter = 0

        for rule in rules(for: settings) {
            let range = NSRange(working.startIndex..., in: working)
            let results = rule.expression.matches(in: working, range: range).reversed()
            for result in results {
                guard let swiftRange = Range(result.range, in: working) else { continue }
                let original = String(working[swiftRange])
                guard !matches.contains(where: { $0.original == original }) else { continue }
                counter += 1
                let token = "[AURA_\(rule.category.uppercased())_\(counter)]"
                working.replaceSubrange(swiftRange, with: token)
                matches.append(PrivacyMatch(category: rule.category, original: original, placeholder: token))
            }
        }
        guard !matches.isEmpty else { return nil }
        return PrivacyReview(original: text, redacted: working, matches: matches.reversed())
    }

    func restore(_ text: String, review: PrivacyReview) -> String {
        review.matches.reduce(text) { partial, match in
            partial.replacingOccurrences(of: match.placeholder, with: match.original)
        }
    }

    private func rules(for settings: PrivacySettings) -> [(category: String, expression: NSRegularExpression)] {
        var patterns: [(String, String)] = []
        if settings.redactEmails {
            patterns.append(("email", #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#))
        }
        if settings.redactPhones {
            patterns.append(("phone", #"(?<!\d)(?:\+?\d{1,3}[ .-]?)?(?:\(?\d{2,4}\)?[ .-]?)?\d{3,4}[ .-]\d{4}(?!\d)"#))
        }
        if settings.redactCards {
            patterns.append(("card", #"(?<!\d)(?:\d[ -]?){13,19}(?!\d)"#))
        }
        if settings.redactSecrets {
            patterns += [
                ("secret", #"(?i)\b(?:sk|rk|pk|ghp|github_pat)_[A-Za-z0-9_\-]{16,}\b"#),
                ("secret", #"(?i)\b(?:api[_-]?key|token|secret|password)\s*[:=]\s*['\"]?[^\s'\"]{8,}"#)
            ]
        }
        patterns += settings.customPatterns.map { ("custom", $0) }
        return patterns.compactMap { category, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (category, expression)
        }
    }
}
