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
        settings = persistence.loadSettings()
        members = persistence.loadMembers()
        selectedMemberID = members.first?.id
        loadConversation()
    }

    var selectedMember: TeamMember? { members.first { $0.id == selectedMemberID } }

    var globalMemory: String { persistence.globalMemory() }

    func select(_ member: TeamMember) {
        selectedMemberID = member.id
        loadConversation()
    }

    func saveSettings() { persistence.saveSettings(settings) }

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

    func chooseAdditionalFolder() {
        let panel = configuredFolderPanel(title: "Allow agent to read a folder")
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

    private func loadConversation() {
        guard let selectedMemberID else { messages = []; return }
        messages = persistence.loadConversation(memberID: selectedMemberID)
    }

    private func send(text: String, displayText: String, attachments: [ChatAttachment], privacyReview: PrivacyReview?) {
        guard let member = selectedMember else { return }
        draft = ""
        pendingAttachments = []
        let user = ConversationMessage(role: .user, content: displayText, attachments: attachments)
        messages.append(user)
        persistence.saveConversation(messages, memberID: member.id)
        isWorking = true

        let history = messages.dropLast()
        let config = settings.provider
        let globalMemory = globalMemory
        let privateMemory = memberMemory(member)
        let workspace = settings.workspacePath.isEmpty ? nil : URL(fileURLWithPath: settings.workspacePath)
        let authorizedFolders = settings.authorizedFolderPaths.map { URL(fileURLWithPath: $0) }
        let agentMode = settings.agentModeEnabled

        Task {
            do {
                let response: String
                if agentMode {
                    response = try await AgentHarness().run(
                        userPrompt: text,
                        member: member,
                        history: Array(history),
                        configuration: config,
                        globalMemory: globalMemory,
                        memberMemory: privateMemory,
                        workspace: workspace,
                        authorizedFolders: authorizedFolders,
                        requestFolder: { name in await self.requestFolderAccess(named: name) },
                        approval: { approval in await self.requestApproval(approval) }
                    )
                } else {
                    let system = [member.systemPrompt, globalMemory.isEmpty ? nil : "Shared user memory:\n\(globalMemory)", privateMemory.isEmpty ? nil : "Your private memory:\n\(privateMemory)"]
                        .compactMap { $0 }
                        .joined(separator: "\n\n")
                    let modelMessages = [ModelMessage(role: "system", content: system)]
                        + history.suffix(16).map { ModelMessage(role: $0.role.rawValue, content: $0.modelContent) }
                        + [ModelMessage(role: "user", content: text)]
                    response = try await OpenAICompatibleClient().complete(messages: modelMessages, configuration: config)
                }
                let restored = privacyReview.map { privacyFilter.restore(response, review: $0) } ?? response
                messages.append(ConversationMessage(role: .assistant, content: restored))
                persistence.saveConversation(messages, memberID: member.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
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
