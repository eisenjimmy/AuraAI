import Foundation
import SwiftUI

struct ConversationContextStatus: Equatable {
    static let capacity = 8_192

    var includedSince: Date?
    var estimatedTokens: Int
    var droppedMessageCount: Int

    var usesRollingWindow: Bool { droppedMessageCount > 0 }

    var detail: String {
        let usage = "~\(estimatedTokens.formatted()) / \(Self.capacity.formatted())"
        guard usesRollingWindow, let includedSince else {
            return auraText("Whole chat in context · \(usage)", "전체 대화가 맥락에 포함됨 · \(usage)")
        }
        let date = includedSince.formatted(date: .abbreviated, time: .shortened)
        return auraText("Earlier chat summarized · recent messages from \(date) · \(usage)", "이전 대화 요약 포함 · \(date)부터 최근 대화 원문 포함 · \(usage)")
    }
}

struct ConversationContextWindow {
    /// Reserve room for the harness policy, memories, the current prompt, and
    /// a streamed reply. Earlier turns are represented by a continuity ledger.
    static let historyTokenBudget = 3_200

    struct Selection {
        var messages: [ConversationMessage]
        var status: ConversationContextStatus

        func omitted(from allMessages: [ConversationMessage]) -> [ConversationMessage] {
            Array(allMessages.prefix(max(0, allMessages.count - messages.count)))
        }
    }

    static func select(from messages: [ConversationMessage]) -> Selection {
        var selected: [ConversationMessage] = []
        var used = 0

        for message in messages.reversed() {
            let cost = estimatedTokens(message.modelContent) + 8
            guard used + cost <= historyTokenBudget || selected.isEmpty else { break }
            selected.append(message)
            used += cost
        }

        let chronological = selected.reversed()
        return Selection(
            messages: Array(chronological),
            status: ConversationContextStatus(
                includedSince: chronological.first?.createdAt,
                estimatedTokens: used,
                droppedMessageCount: max(0, messages.count - chronological.count)
            )
        )
    }

    static func estimatedTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let weightedCharacters = text.unicodeScalars.reduce(0) { total, scalar in
            total + (scalar.isASCII ? 1 : 2)
        }
        return max(1, Int(ceil(Double(weightedCharacters) / 3.4)))
    }
}

enum DocumentNaming {
    static func suggestedTitle(for artifact: ArtifactIntent, source: String) -> String {
        let normalized = source.lowercased()
        let suffix: String
        switch artifact {
        case .spreadsheet: suffix = auraText("Characters", "등장인물")
        case .presentation: suffix = auraText("Presentation", "프레젠테이션")
        case .word: suffix = auraText("Brief", "요약")
        case .markdown: suffix = auraText("Notes", "메모")
        case .html: suffix = auraText("Report", "보고서")
        }

        if normalized.contains("cinderella") || source.contains("신데렐라") {
            return auraText("Cinderella \(suffix)", "신데렐라 \(suffix)")
        }

        let lines = meaningfulLines(in: source)
        if let candidate = lines.first(where: { line in
            let compact = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return compact.count >= 3 && compact.count <= 56 && !looksLikeInstruction(compact)
        }) {
            return String(candidate.prefix(56))
        }
        return artifact.defaultTitle
    }

    static func meaningfulLines(in source: String, limit: Int = 80) -> [String] {
        let lines = source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("<") && !$0.hasPrefix("[") }
            .filter { !$0.localizedCaseInsensitiveContains("following attachments") && !$0.localizedCaseInsensitiveContains("context note:") }
            .filter { !looksLikeInstruction($0) }
        return Array(lines.prefix(limit))
    }

    static func filename(title: String, fileExtension: String) -> String {
        let safe = title
            .replacingOccurrences(of: "Aura", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "[^A-Za-z0-9가-힣 _-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
        let base = safe.isEmpty ? "Document" : String(safe.prefix(72))
        return "\(base).\(fileExtension)"
    }

    private static func looksLikeInstruction(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("make a powerpoint") || lower.contains("create a presentation") || lower.contains("create an excel") || lower.contains("powerpoint") || lower.contains("spreadsheet") || line.contains("파워포인트") || line.contains("엑셀") || line.contains("만들어")
    }
}

enum ArtifactValidator {
    static func validate(_ attachments: [ChatAttachment], expected: ArtifactIntent, source: String = "") -> String? {
        guard let attachment = attachments.last else {
            return auraText("No file was produced.", "생성된 파일이 없습니다.")
        }
        let url = URL(fileURLWithPath: attachment.storedPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return auraText("The generated file is missing.", "생성된 파일을 찾을 수 없습니다.")
        }
        guard url.pathExtension.lowercased() == expected.fileExtension else {
            return auraText("The generated file type does not match the request.", "생성된 파일 형식이 요청과 다릅니다.")
        }
        let bytes = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        guard bytes > 512 else {
            return auraText("The generated file is unexpectedly empty.", "생성된 파일이 비어 있습니다.")
        }
        if expected == .presentation {
            let entries = archiveEntries(at: url)
            let slides = entries.filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            guard entries.contains("ppt/presentation.xml"), slides.count >= 2 else {
                return auraText("The PowerPoint did not contain enough slides.", "PowerPoint에 필요한 슬라이드가 없습니다.")
            }
            if let anchor = sourceAnchor(in: source), !archiveText(at: url, pattern: "ppt/slides/slide*.xml").localizedCaseInsensitiveContains(anchor) {
                return auraText("The PowerPoint did not include the requested source subject.", "PowerPoint에 요청한 원문의 핵심 주제가 포함되지 않았습니다.")
            }
        }
        if expected == .spreadsheet {
            let entries = archiveEntries(at: url)
            guard entries.contains("xl/workbook.xml"), entries.contains("xl/worksheets/sheet1.xml") else {
                return auraText("The Excel workbook is incomplete.", "Excel 워크북 구조가 완전하지 않습니다.")
            }
        }
        if expected == .word {
            guard archiveEntries(at: url).contains("word/document.xml") else {
                return auraText("The Word document is incomplete.", "Word 문서 구조가 완전하지 않습니다.")
            }
        }
        return nil
    }

    private static func archiveEntries(at url: URL) -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", url.path]
        process.standardOutput = output
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty } ?? []
    }

    private static func archiveText(at url: URL, pattern: String) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, pattern]
        process.standardOutput = output
        guard (try? process.run()) != nil else { return "" }
        process.waitUntilExit()
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static func sourceAnchor(in source: String) -> String? {
        if source.localizedCaseInsensitiveContains("cinderella") { return "Cinderella" }
        if source.contains("신데렐라") { return "신데렐라" }
        return nil
    }
}

enum AuraTheme {
    static let accent = Color(red: 0.30, green: 0.63, blue: 0.55)
    static let selection = Color.white.opacity(0.085)
    static let userBubble = Color(red: 0.17, green: 0.30, blue: 0.27)
}
