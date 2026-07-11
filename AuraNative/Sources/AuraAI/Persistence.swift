import Foundation

enum AuraStoreError: LocalizedError {
    case invalidWorkspace

    var errorDescription: String? {
        switch self {
        case .invalidWorkspace: return auraText("Choose a write folder before enabling tools.", "도구를 사용하기 전에 저장 폴더를 선택하세요.")
        }
    }
}

final class AuraPersistence {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        root = (support ?? fileManager.homeDirectoryForCurrentUser)
            .appendingPathComponent(AuraEdition.current.storageFolder, isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func loadSettings() -> AuraSettings { load(AuraSettings.self, from: "settings.json") ?? AuraSettings() }
    func saveSettings(_ settings: AuraSettings) { save(settings, to: "settings.json") }

    func loadMembers() -> [TeamMember] {
        guard let members = load([TeamMember].self, from: "team.json") else { return TeamMember.defaults }
        // Replace the short-lived generic native prototype roster, but never
        // overwrite an actual user-created team.
        if !members.isEmpty, members.allSatisfy({ TeamMember.legacyNativeNames.contains($0.name) }) {
            return TeamMember.defaults
        }
        let migrated = TeamMember.migratingKoreanLegacyPrompts(members)
        if migrated != members { saveMembers(migrated) }
        return migrated
    }
    func saveMembers(_ members: [TeamMember]) { save(members, to: "team.json") }

    func loadConversation(memberID: UUID) -> [ConversationMessage] {
        load([ConversationMessage].self, from: "conversations/\(memberID.uuidString).json") ?? []
    }

    func saveConversation(_ messages: [ConversationMessage], memberID: UUID) {
        save(messages, to: "conversations/\(memberID.uuidString).json")
    }

    func globalMemory() -> String { loadText("memory/global.md") }
    func saveGlobalMemory(_ text: String) { saveText(text, to: "memory/global.md") }
    func memberMemory(_ memberID: UUID) -> String { loadText("memory/members/\(memberID.uuidString).md") }
    func saveMemberMemory(_ text: String, memberID: UUID) { saveText(text, to: "memory/members/\(memberID.uuidString).md") }

    var memoryVaultRoot: URL { root.appendingPathComponent("memory-vault", isDirectory: true) }
    func globalMemoryVault() -> MarkdownMemoryVault {
        MarkdownMemoryVault(root: memoryVaultRoot.appendingPathComponent("global", isDirectory: true))
    }
    func memberMemoryVault(_ memberID: UUID) -> MarkdownMemoryVault {
        MarkdownMemoryVault(root: memoryVaultRoot
            .appendingPathComponent("characters", isDirectory: true)
            .appendingPathComponent(memberID.uuidString, isDirectory: true))
    }

    func importAvatar(from source: URL, memberID: UUID) -> String? {
        let allowed = ["png", "jpg", "jpeg", "webp", "gif"]
        let ext = source.pathExtension.lowercased()
        guard allowed.contains(ext) else { return nil }
        let destination = root.appendingPathComponent("avatars/\(memberID.uuidString).\(ext)")
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }

    func importAttachment(from source: URL) throws -> URL {
        let cleanedName = source.lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let destination = root
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString)-\(cleanedName)")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func load<T: Decodable>(_ type: T.Type, from relativePath: String) -> T? {
        let url = root.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to relativePath: String) {
        guard let data = try? encoder.encode(value) else { return }
        write(data, to: relativePath)
    }

    private func loadText(_ relativePath: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)) ?? ""
    }

    private func saveText(_ text: String, to relativePath: String) {
        write(Data(text.utf8), to: relativePath)
    }

    private func write(_ data: Data, to relativePath: String) {
        let destination = root.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.appendingPathExtension("tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
        }
    }
}
