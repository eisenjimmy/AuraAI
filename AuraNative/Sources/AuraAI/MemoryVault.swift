import Foundation

struct MarkdownMemoryNote: Equatable {
    var slug: String
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
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

        let note = MarkdownMemoryNote(
            slug: "memory-\(stableID(body))",
            title: String(body.prefix(80)),
            body: body,
            createdAt: Date(),
            updatedAt: Date()
        )
        save(note)
        return note
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

        return files
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "MEMORY.md" }
            .compactMap(parse)
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
            updatedAt: Date()
        )
        let formatter = ISO8601DateFormatter()
        let text = """
        ---
        title: \(yaml(stored.title))
        type: fact
        importance: 3
        created: \(formatter.string(from: stored.createdAt))
        updated: \(formatter.string(from: stored.updatedAt))
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
            updatedAt: fields["updated"].flatMap(formatter.date(from:)) ?? fallback
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
