import Foundation

struct MarkdownMemoryNote: Equatable {
    var slug: String
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var expiresAt: Date? = nil
}

enum MemoryRetention: String, CaseIterable, Identifiable {
    case longTerm
    case sevenDays
    case thirtyDays

    var id: String { rawValue }
    var expiresAt: Date? {
        switch self {
        case .longTerm: return nil
        case .sevenDays: return Calendar.current.date(byAdding: .day, value: 7, to: Date())
        case .thirtyDays: return Calendar.current.date(byAdding: .day, value: 30, to: Date())
        }
    }
    var title: String {
        switch self {
        case .longTerm: return auraText("Long-term", "장기 기억")
        case .sevenDays: return auraText("Expires in 7 days", "7일 후 만료")
        case .thirtyDays: return auraText("Expires in 30 days", "30일 후 만료")
        }
    }
}

/// Obsidian-compatible memory notes. Each friend owns a separate vault.
final class MarkdownMemoryVault {
    private let root: URL
    private let fileManager: FileManager

    init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var url: URL { root }

    @discardableResult
    func captureIfRequested(_ message: String) -> MarkdownMemoryNote? {
        guard isExplicitMemoryRequest(message) else { return nil }
        let body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        return save(body: body, retention: inferredRetention(for: body))
    }

    @discardableResult
    func save(body: String, retention: MemoryRetention = .longTerm) -> MarkdownMemoryNote {
        let cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let note = MarkdownMemoryNote(
            slug: "memory-\(stableID(cleaned))",
            title: String(cleaned.prefix(80)),
            body: cleaned,
            createdAt: now,
            updatedAt: now,
            expiresAt: retention.expiresAt
        )
        save(note)
        return note
    }

    func delete(_ note: MarkdownMemoryNote) {
        try? fileManager.removeItem(at: noteURL(note.slug))
        writeIndex()
    }

    func recall(_ query: String, limit: Int = 4) -> [MarkdownMemoryNote] {
        let queryTerms = terms(in: query)
        guard !queryTerms.isEmpty else { return [] }

        return list()
            .compactMap { note -> (MarkdownMemoryNote, Double)? in
                let candidate = "\(note.title) \(note.body)"
                let candidateTerms = terms(in: candidate)
                let overlap = queryTerms.intersection(candidateTerms).count
                let exact = candidate.localizedCaseInsensitiveContains(query)
                let score = exact ? 1 : Double(overlap) / Double(queryTerms.count)
                return score >= 0.18 ? (note, score) : nil
            }
            .sorted {
                $0.1 == $1.1 ? $0.0.updatedAt > $1.0.updatedAt : $0.1 > $1.1
            }
            .prefix(limit)
            .map(\.0)
    }

    func list() -> [MarkdownMemoryNote] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let notes = files
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "MEMORY.md" }
            .compactMap(parse)
        for note in notes where note.expiresAt.map({ $0 <= Date() }) == true {
            try? fileManager.removeItem(at: noteURL(note.slug))
        }
        return notes
            .filter { $0.expiresAt.map({ $0 > Date() }) ?? true }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save(_ note: MarkdownMemoryNote) {
        let existing = parse(noteURL(note.slug))
        let createdAt = existing?.createdAt ?? note.createdAt
        let stored = MarkdownMemoryNote(
            slug: note.slug,
            title: note.title,
            body: note.body,
            createdAt: createdAt,
            updatedAt: Date(),
            expiresAt: note.expiresAt
        )
        let formatter = ISO8601DateFormatter()
        let text = """
        ---
        title: \(yaml(stored.title))
        type: fact
        importance: 3
        created: \(formatter.string(from: stored.createdAt))
        updated: \(formatter.string(from: stored.updatedAt))
        \(stored.expiresAt.map { "expires: \(formatter.string(from: $0))" } ?? "")
        ---

        \(stored.body.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        try? text.write(to: noteURL(stored.slug), atomically: true, encoding: .utf8)
        writeIndex()
    }

    private func parse(_ url: URL) -> MarkdownMemoryNote? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let separator = "\n---\n"
        let parts = raw.components(separatedBy: separator)
        let header: String
        let body: String
        if raw.hasPrefix("---\n"), parts.count >= 2 {
            header = String(parts[0].dropFirst(4))
            body = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            header = ""
            body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !body.isEmpty else { return nil }
        let fields = Dictionary(uniqueKeysWithValues: header
            .split(separator: "\n")
            .compactMap { line -> (String, String)? in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                return (String(line[..<colon]).trimmingCharacters(in: .whitespaces), String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            })
        let formatter = ISO8601DateFormatter()
        let fallback = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        return MarkdownMemoryNote(
            slug: url.deletingPathExtension().lastPathComponent,
            title: fields["title"] ?? url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " "),
            body: body,
            createdAt: fields["created"].flatMap(formatter.date(from:)) ?? fallback,
            updatedAt: fields["updated"].flatMap(formatter.date(from:)) ?? fallback,
            expiresAt: fields["expires"].flatMap(formatter.date(from:))
        )
    }

    private func writeIndex() {
        let lines = ["# Memory Index", "", "_\(list().count) memories. Auto-generated by Aura._", ""]
            + list().map { "- [[\($0.slug)]] - \($0.title)" }
        try? lines.joined(separator: "\n").write(
            to: root.appendingPathComponent("MEMORY.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func noteURL(_ slug: String) -> URL {
        root.appendingPathComponent("\(slug).md")
    }

    private func isExplicitMemoryRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("remember") || lower.contains("keep in mind") || lower.contains("note that")
            || text.contains("기억해") || text.contains("기억해줘") || text.contains("기억해 둬") || text.contains("알아둬")
    }

    private func inferredRetention(for text: String) -> MemoryRetention {
        let lower = text.lowercased()
        if lower.contains("today") || lower.contains("temporary") || text.contains("오늘") || text.contains("잠깐") { return .sevenDays }
        if lower.contains("this month") || text.contains("이번 달") { return .thirtyDays }
        return .longTerm
    }

    private func terms(in text: String) -> Set<String> {
        let stopWords: Set<String> = ["a", "an", "and", "are", "at", "can", "do", "for", "i", "in", "is", "it", "my", "of", "or", "that", "the", "to", "what", "where", "you", "your"]
        return Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) })
    }

    private func yaml(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: ":", with: "-")
    }

    private func stableID(_ text: String) -> String {
        String(text.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }, radix: 16)
    }
}
