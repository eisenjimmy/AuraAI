import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AuraStore: ObservableObject {
    @Published var settings: AuraSettings
    @Published var members: [TeamMember]
    @Published var selectedMemberID: UUID?
    @Published var messages: [ConversationMessage] = []
    @Published var draft = ""
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isExtractingAttachments = false
    @Published var isWorking = false
    @Published var activeWorkingMemberID: UUID?
    @Published var harnessEvents: [AgentHarnessEvent] = []
    @Published var contextStatus = ConversationContextStatus(includedSince: nil, estimatedTokens: 0, droppedMessageCount: 0)
    @Published var previewAttachment: ChatAttachment?
    @Published var pendingPrivacy: PrivacyReview?
    @Published var pendingApproval: AgentApproval?
    @Published var errorMessage: String?
    @Published var isShowingSettings = false
    @Published var isShowingGlobalMemory = false
    @Published var memoryMember: TeamMember?
    @Published var editingMember: TeamMember?

    private let persistence = AuraPersistence()
    private let privacyFilter = PrivacyFilter()
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var privacyDraft = ""
    private var privacyAttachments: [ChatAttachment] = []

    init() {
        var loadedSettings = persistence.loadSettings()
        if loadedSettings.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let defaultWorkspace = AuraWriteFolder.url
            try? FileManager.default.createDirectory(at: defaultWorkspace, withIntermediateDirectories: true)
            loadedSettings.workspacePath = defaultWorkspace.path
            persistence.saveSettings(loadedSettings)
        }
        settings = loadedSettings
        members = persistence.loadMembers()
        migrateLegacyMemoryIntoVaults()
        migrateDefaultRosterIfNeeded()
        selectedMemberID = members.first?.id
        loadConversation()
    }

    var selectedMember: TeamMember? { members.first { $0.id == selectedMemberID } }
    var skillSettings: AgentSkillSettings { settings.skillSettings ?? AgentSkillSettings() }
    func effectiveSkills(for member: TeamMember) -> AgentSkillSettings { skillSettings.limited(to: member) }
    func isWorking(for member: TeamMember) -> Bool { isWorking && activeWorkingMemberID == member.id }

    func applyProviderPreset(_ kind: ProviderKind) {
        settings.provider.kind = kind
        settings.provider.baseURL = kind.defaultBaseURL
        if !kind.defaultModel.isEmpty {
            settings.provider.model = kind.defaultModel
        }
        saveSettings()
    }

    var globalMemory: String { persistence.globalMemory() }
    var globalMemoryVaultURL: URL { persistence.globalMemoryVault().url }
    func memberMemoryVaultURL(_ member: TeamMember) -> URL { persistence.memberMemoryVault(member.id).url }
    func globalMemoryVault() -> MarkdownMemoryVault { persistence.globalMemoryVault() }
    func memberMemoryVault(_ member: TeamMember) -> MarkdownMemoryVault { persistence.memberMemoryVault(member.id) }

    func select(_ member: TeamMember) {
        selectedMemberID = member.id
        loadConversation()
    }

    func saveSettings() { persistence.saveSettings(settings) }

    func setSkillEnabled(_ enabled: Bool, for skill: AgentSkill) {
        var updated = skillSettings
        updated.setEnabled(enabled, for: skill)
        settings.skillSettings = updated
        saveSettings()
    }

    func createMember(role: TeamRole) {
        let member = TeamMember(
            id: UUID(),
            name: role.title,
            role: role,
            tagline: auraText("A new member of your AI team.", "새로운 AI 친구입니다."),
            avatarPath: nil,
            avatarAsset: nil,
            customInstructions: "",
            createdAt: .now
        )
        members.append(member)
        persistence.saveMembers(members)
        select(member)
    }

    func deleteSelectedMember() {
        guard let selectedMember, !TeamMember.defaults.contains(where: { $0.id == selectedMember.id }) else { return }
        members.removeAll { $0.id == selectedMember.id }
        persistence.saveMembers(members)
        selectedMemberID = members.first?.id
        loadConversation()
    }

    func saveMember(_ member: TeamMember) {
        guard let index = members.firstIndex(where: { $0.id == member.id }) else { return }
        members[index] = member
        persistence.saveMembers(members)
    }

    func setInitialTeam(_ initialTeam: [TeamMember]) {
        members = initialTeam
        selectedMemberID = initialTeam.first?.id
        persistence.saveMembers(initialTeam)
        loadConversation()
    }

    private func migrateDefaultRosterIfNeeded() {
        guard (settings.defaultRosterRevision ?? 0) < TeamMember.currentDefaultRosterRevision else { return }
        let doctor = TeamMember.doctorDefault
        if !members.contains(where: { $0.id == doctor.id }) {
            members.append(doctor)
            persistence.saveMembers(members)
        }
        settings.defaultRosterRevision = TeamMember.currentDefaultRosterRevision
        saveSettings()
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.workspacePath = url.path
            saveSettings()
        }
    }

    func useDefaultWorkspace() {
        let defaultWorkspace = AuraWriteFolder.url
        try? FileManager.default.createDirectory(at: defaultWorkspace, withIntermediateDirectories: true)
        settings.workspacePath = defaultWorkspace.path
        saveSettings()
    }

    func chooseAdditionalFolder() {
        let panel = configuredFolderPanel(title: auraText("Allow agent to read a folder", "에이전트 읽기 폴더 허용"))
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addAuthorizedFolder(url)
    }

    func requestFolderAccess(named suggestedName: String) async -> URL? {
        let cleanedName = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = cleanedName.isEmpty ? "a folder" : "the \(cleanedName) folder"
        let approved = await requestApproval(AgentApproval(
            kind: .folderAccess,
            title: "Allow Aura to read \(label)",
            detail: "Aura will open a Finder picker. Only the folder you select will be available for read-only listing and file inspection during agent work. File writes and shell commands remain limited to the selected workspace."
        ))
        guard approved else { return nil }

        let panel = configuredFolderPanel(title: "Choose \(label)")
        if cleanedName.caseInsensitiveCompare("downloads") == .orderedSame {
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        addAuthorizedFolder(url)
        return url.standardizedFileURL
    }

    func revokeFolderAccess(_ path: String) {
        settings.authorizedFolderPaths.removeAll { $0 == path }
        saveSettings()
    }

    func chooseAvatar(for member: TeamMember) {
        guard let path = importAvatar(for: member) else { return }
        var updated = member
        updated.avatarPath = path
        saveMember(updated)
    }

    func importAvatar(for member: TeamMember) -> String? {
        let panel = NSOpenPanel()
        panel.title = auraText("Choose profile image", "프로필 이미지 선택")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["png", "jpg", "jpeg", "webp", "gif"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let source = panel.url else { return nil }
        return persistence.importAvatar(from: source, memberID: member.id)
    }

    func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.title = auraText("Attach files", "파일 첨부")
        panel.message = auraText("Aura can read images, PDF, Word, Excel, and text files up to 20 MB each.", "Aura는 파일당 최대 20MB의 이미지, PDF, Word, Excel, 텍스트 파일을 읽을 수 있습니다.")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "bmp", "gif", "webp", "pdf", "docx", "rtf", "xlsx", "csv", "tsv", "txt", "md", "json", "html", "htm", "xml"]
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }

        isExtractingAttachments = true
        let sources = panel.urls
        Task {
            defer { isExtractingAttachments = false }
            for source in sources {
                do {
                    try AttachmentExtractor.validateFileSize(source)
                    let stored = try persistence.importAttachment(from: source)
                    let attachment = try await Task.detached {
                        try AttachmentExtractor.extract(from: stored, displayName: source.lastPathComponent)
                    }.value
                    pendingAttachments.append(attachment)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func removePendingAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func export(_ attachment: ChatAttachment) {
        let source = URL(fileURLWithPath: attachment.storedPath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            errorMessage = auraText("That file is no longer available.", "해당 파일을 더 이상 찾을 수 없습니다.")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.fileName
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginSend() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !pendingAttachments.isEmpty), !isWorking, !isExtractingAttachments, selectedMember != nil else { return }
        let visibleText = text.isEmpty ? auraText("Please review the attached file.", "첨부한 파일을 검토해줘.") : text
        let attachments = pendingAttachments
        let outbound = AttachmentContext.compose(prompt: visibleText, attachments: attachments)
        if settings.provider.kind.isCloud, settings.privacy.enabled,
           let review = privacyFilter.inspect(outbound, settings: settings.privacy) {
            privacyDraft = visibleText
            privacyAttachments = attachments
            pendingPrivacy = review
            return
        }
        send(text: outbound, displayText: visibleText, attachments: attachments, privacyReview: nil)
    }

    func approvePrivacy() {
        guard let pendingPrivacy else { return }
        self.pendingPrivacy = nil
        send(
            text: pendingPrivacy.redacted,
            displayText: privacyDraft,
            attachments: privacyAttachments,
            privacyReview: pendingPrivacy
        )
        privacyDraft = ""
        privacyAttachments = []
    }

    func cancelPrivacy() {
        pendingPrivacy = nil
        privacyDraft = ""
        privacyAttachments = []
    }

    func resolveApproval(_ allowed: Bool) {
        pendingApproval = nil
        approvalContinuation?.resume(returning: allowed)
        approvalContinuation = nil
    }

    func requestApproval(_ approval: AgentApproval) async -> Bool {
        await withCheckedContinuation { continuation in
            approvalContinuation = continuation
            pendingApproval = approval
        }
    }

    func saveGlobalMemory(_ text: String) { persistence.saveGlobalMemory(text) }
    func saveMemberMemory(_ text: String, member: TeamMember) { persistence.saveMemberMemory(text, memberID: member.id) }
    func memberMemory(_ member: TeamMember) -> String { persistence.memberMemory(member.id) }

    private func memberMemoryContext(for member: TeamMember, query: String) -> String {
        let vault = persistence.memberMemoryVault(member.id)
        _ = vault.captureIfRequested(query)
        let notes = vault.recall(query)
        let manualMemory = memberMemory(member)
        let recalled = notes.map { "- \($0.body)" }.joined(separator: "\n")
        return [
            manualMemory.isEmpty ? nil : "Private memory:\n\(manualMemory)",
            recalled.isEmpty ? nil : "Recalled private Markdown memories:\n\(recalled)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    private func globalMemoryContext(query: String) -> String {
        let notes = persistence.globalMemoryVault().recall(query)
        let legacyMemory = globalMemory
        let recalled = notes.map { "- \($0.body)" }.joined(separator: "\n")
        return [
            legacyMemory.isEmpty ? nil : "Shared memory:\n\(legacyMemory)",
            recalled.isEmpty ? nil : "Recalled shared Markdown memories:\n\(recalled)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    private func migrateLegacyMemoryIntoVaults() {
        let shared = persistence.globalMemory()
        if !shared.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = persistence.globalMemoryVault().save(body: shared)
            persistence.saveGlobalMemory("")
        }
        for member in members {
            let legacy = persistence.memberMemory(member.id)
            if !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = persistence.memberMemoryVault(member.id).save(body: legacy)
                persistence.saveMemberMemory("", memberID: member.id)
            }
        }
    }

    private func loadConversation() {
        guard let selectedMemberID else { messages = []; return }
        messages = persistence.loadConversation(memberID: selectedMemberID)
        contextStatus = ConversationContextWindow.select(from: messages).status
    }

    private func send(text: String, displayText: String, attachments: [ChatAttachment], privacyReview: PrivacyReview?) {
        guard let member = selectedMember else { return }
        draft = ""
        pendingAttachments = []
        let user = ConversationMessage(role: .user, content: displayText, attachments: attachments)
        messages.append(user)
        persistence.saveConversation(messages, memberID: member.id)
        isWorking = true
        activeWorkingMemberID = member.id
        harnessEvents = []

        let history = messages.dropLast()
        let config = settings.provider
        let globalMemory = globalMemoryContext(query: text)
        let privateMemory = memberMemoryContext(for: member, query: text)
        let workspace = settings.workspacePath.isEmpty ? nil : URL(fileURLWithPath: settings.workspacePath)
        let authorizedFolders = settings.authorizedFolderPaths.map { URL(fileURLWithPath: $0) }
        let skills = effectiveSkills(for: member)
        // Decide the output type only from what the person typed. `text` also
        // includes attachment contents, which may mention unrelated formats.
        let requestedArtifact = ArtifactIntent.requested(in: displayText)
        let boundedHistory = ConversationContextWindow.select(from: Array(history))
        contextStatus = boundedHistory.status

        Task {
            do {
                let response: String
                let responseAttachments: [ChatAttachment]
                let result = try await AgentHarness().run(
                    userPrompt: text,
                    member: member,
                    history: boundedHistory.messages,
                    configuration: config,
                    globalMemory: globalMemory,
                    memberMemory: privateMemory,
                    workspace: workspace,
                    authorizedFolders: authorizedFolders,
                    skills: skills,
                    requestedArtifact: requestedArtifact,
                    attachments: attachments,
                    requestFolder: { name in await self.requestFolderAccess(named: name) },
                    approval: { approval in await self.requestApproval(approval) },
                    onEvent: { event in self.harnessEvents.append(event) }
                )
                response = result.response
                responseAttachments = result.attachments
                let restored = privacyReview.map { privacyFilter.restore(response, review: $0) } ?? response
                messages.append(ConversationMessage(role: .assistant, content: restored, attachments: responseAttachments))
                persistence.saveConversation(messages, memberID: member.id)
                if selectedMemberID == member.id {
                    contextStatus = ConversationContextWindow.select(from: messages).status
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
            if activeWorkingMemberID == member.id { activeWorkingMemberID = nil }
        }
    }

    private func configuredFolderPanel(title: String) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = auraText("Aura receives read-only agent access only to the folder you select.", "Aura는 선택한 폴더에만 읽기 전용으로 접근합니다.")
        panel.prompt = auraText("Allow folder", "폴더 허용")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel
    }

    private func addAuthorizedFolder(_ url: URL) {
        let path = url.standardizedFileURL.path
        if !settings.authorizedFolderPaths.contains(path) {
            settings.authorizedFolderPaths.append(path)
            settings.authorizedFolderPaths.sort()
            saveSettings()
        }
    }
}
