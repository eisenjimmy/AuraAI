import AppKit
import QuickLookUI
import SwiftUI
import WebKit

struct OnboardingView: View {
    @EnvironmentObject private var store: AuraStore
    @State private var step = 0
    @State private var selectedFriendIDs: Set<UUID> = Set(TeamMember.defaults.map(\.id))

    private var labels: [String] {
        AuraEdition.current == .korean ? ["환영", "모델", "개인정보", "친구"] : ["Welcome", "Brain", "Privacy", "Team"]
    }

    var body: some View {
        onboardingShell
    }

    private var onboardingShell: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            HStack(spacing: 0) {
                onboardingProgress
                onboardingContent
            }
            .frame(width: 900, height: 580)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)))
            .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
            .padding(28)
        }
    }

    private var onboardingProgress: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 18, weight: .medium))
                Text("Aura").font(.headline)
            }
            Text(auraText("Friends with expertise, private to your Mac.", "전문성을 가진 친구들, 내 Mac 안에서 안전하게."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    HStack(spacing: 9) {
                        Image(systemName: index < step ? "checkmark.circle.fill" : index == step ? "circle.inset.filled" : "circle")
                            .foregroundStyle(index <= step ? AuraTheme.accent : Color.secondary.opacity(0.55))
                        Text(label).foregroundStyle(index == step ? Color.primary : Color.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .frame(width: 210, alignment: .leading)
        .padding(28)
        .background(.thinMaterial)
    }

    private var onboardingContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            page
            Spacer(minLength: 0)
            HStack {
                if step > 0 { Button(auraText("Back", "뒤로")) { step -= 1 }.buttonStyle(.bordered) }
                Spacer()
                Button(step == 3 ? auraText("Open Aura", "Aura 시작") : auraText("Continue", "계속")) {
                    if step == 3 {
                        createSelectedTeam()
                        store.settings.onboarded = true
                        store.saveSettings()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(step == 3 && selectedFriendIDs.isEmpty)
            }
        }
        .padding(38)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder private var page: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 14) {
                Text(auraText("Build your AI team.", "나만의 AI 친구 팀을 만나보세요."))
                    .font(.system(size: 34, weight: .bold))
                Text(auraText("Aura gives each teammate a clear role, their own memory, and only the tools you permit. Start private on your Mac, then connect a cloud model when the work calls for it.", "각 친구는 고유한 역할과 기억을 가지며, 허용한 도구만 사용합니다. Mac에서 비공개로 시작하고 필요할 때 클라우드 모델을 연결하세요."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case 1:
            VStack(alignment: .leading, spacing: 16) {
                Text(auraText("Choose a brain", "AI 모델 선택"))
                    .font(.system(size: 30, weight: .bold))
                Text(auraText("You can change this any time in Settings.", "설정에서 언제든 바꿀 수 있습니다."))
                    .foregroundStyle(.secondary)
                Picker(auraText("Provider", "제공자"), selection: $store.settings.provider.kind) {
                    ForEach(ProviderKind.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(auraText("Server URL", "서버 URL"), text: $store.settings.provider.baseURL)
                        TextField(auraText("Model", "모델"), text: $store.settings.provider.model)
                        if store.settings.provider.kind.isCloud {
                            SecureField(auraText("API key", "API 키"), text: $store.settings.provider.apiKey)
                        } else {
                            Text(auraText("Local default: your llama.cpp server at 127.0.0.1:8080. Aura never sends local-model prompts to a cloud service.", "기본 로컬 연결은 127.0.0.1:8080의 llama.cpp 서버입니다. 로컬 모델의 프롬프트는 클라우드로 보내지 않습니다."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(4)
                } label: {
                    Text(auraText("Connection", "연결"))
                }
            }
        case 2:
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.blue)
                Text(auraText("Keep private details private", "민감한 정보는 비공개로"))
                    .font(.system(size: 30, weight: .bold))
                Text(auraText("Before a cloud request, Aura can locally replace emails, phone numbers, card numbers, and likely API secrets with placeholders. You review every replacement. Local model requests never leave your Mac and are not filtered.", "클라우드 요청 전에 이메일, 전화번호, 카드번호, API 비밀값을 로컬에서 가리고 직접 확인할 수 있습니다. 로컬 모델 요청은 Mac을 떠나지 않습니다."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(auraText("Review sensitive details before cloud requests", "클라우드 요청 전 민감 정보 검토"), isOn: $store.settings.privacy.enabled)
                    .toggleStyle(.switch)
            }
        default:
            VStack(alignment: .leading, spacing: 16) {
                Text(auraText("Choose your friends", "함께할 친구 선택"))
                    .font(.system(size: 30, weight: .bold))
                Text(auraText("Each friend has their own personality, portrait, conversation, and private memory. Their expertise is there when you need it.", "각 친구는 고유한 성격, 프로필, 대화, 개인 기억을 가집니다. 필요할 때 각자의 전문성을 활용하세요."))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(TeamMember.defaults) { friend in
                        Button {
                            if selectedFriendIDs.contains(friend.id) { selectedFriendIDs.remove(friend.id) } else { selectedFriendIDs.insert(friend.id) }
                        } label: {
                            HStack(spacing: 10) {
                                TeamAvatar(member: friend, size: 42)
                                VStack(alignment: .leading) {
                                    Text(friend.name).fontWeight(.medium)
                                    Text(friend.role.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(friend.tagline)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: selectedFriendIDs.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedFriendIDs.contains(friend.id) ? .blue : .gray)
                    }
                }
            }
        }
    }

    private func createSelectedTeam() {
        let defaults = TeamMember.defaults.filter { selectedFriendIDs.contains($0.id) }
        guard !defaults.isEmpty else { return }
        store.setInitialTeam(defaults)
    }
}

struct AuraWorkspaceView: View {
    @EnvironmentObject private var store: AuraStore
    @State private var isShowingAddMember = false

    var body: some View {
        NavigationSplitView {
            FriendsSidebar(isShowingAddMember: $isShowingAddMember)
        } detail: {
            if let member = store.selectedMember {
                if let attachment = store.previewAttachment {
                    HSplitView {
                        ChatView(member: member)
                            .frame(minWidth: 520, idealWidth: 860)
                        ArtifactPreviewPane(attachment: attachment)
                            .frame(minWidth: 340, idealWidth: 520)
                    }
                } else {
                    ChatView(member: member)
                }
            } else {
                ContentUnavailableView(auraText("Choose a teammate", "친구를 선택하세요"), systemImage: "person.2")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        .sheet(isPresented: $isShowingAddMember) { AddMemberSheet() }
        .sheet(isPresented: $store.isShowingSettings) { SettingsView() }
        .sheet(isPresented: $store.isShowingGlobalMemory) {
            MemoryVaultSheet(title: auraText("Global memory", "공통 기억"), vault: store.globalMemoryVault())
        }
        .sheet(item: $store.memoryMember) { member in
            MemoryVaultSheet(title: auraText("What \(member.name) remembers", "\(member.name)이 기억하는 내용"), vault: store.memberMemoryVault(member))
        }
        .sheet(item: $store.editingMember) { member in FriendEditor(member: member) }
        .sheet(item: $store.pendingPrivacy) { review in PrivacyReviewSheet(review: review) }
        .sheet(item: $store.pendingApproval) { approval in AgentApprovalSheet(approval: approval) }
        .alert("Aura", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button(auraText("OK", "확인"), role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct FriendsSidebar: View {
    @EnvironmentObject private var store: AuraStore
    @Binding var isShowingAddMember: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(AuraTheme.accent)
                Text("Aura").font(.headline)
                Spacer()
                Button { isShowingAddMember = true } label: { Image(systemName: "person.badge.plus") }
                    .buttonStyle(.plain)
                    .help(auraText("Add friend", "친구 추가"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            Text(auraText("FRIENDS", "친구"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(store.members) { member in
                        FriendRow(member: member, isSelected: member.id == store.selectedMemberID, isWorking: store.isWorking(for: member))
                            .onTapGesture { store.select(member) }
                            .contextMenu {
                                Button(auraText("Edit friend", "친구 편집")) { store.editingMember = member }
                                Button(auraText("Open memory", "기억 열기")) { store.memoryMember = member }
                                if !TeamMember.defaults.contains(where: { $0.id == member.id }) {
                                    Button(auraText("Remove", "삭제"), role: .destructive) { store.select(member); store.deleteSelectedMember() }
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
            }
            Spacer(minLength: 12)
            Divider()
            VStack(spacing: 4) {
                SidebarAction(title: auraText("Global memory", "공통 기억"), symbol: "brain.head.profile") { store.isShowingGlobalMemory = true }
                SidebarAction(title: auraText("Settings", "설정"), symbol: "gearshape") { store.isShowingSettings = true }
            }
            .padding(10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SidebarAction: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct FriendRow: View {
    var member: TeamMember
    var isSelected: Bool
    var isWorking: Bool

    var body: some View {
        HStack(spacing: 10) {
            TeamAvatar(member: member, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(member.name).fontWeight(.medium)
                    if isWorking { ProgressView().controlSize(.mini) }
                }
                Text(member.role.title)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.72) : Color.secondary)
                Text(isWorking ? auraText("Typing...", "입력 중...") : member.tagline)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isSelected ? AuraTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct TeamAvatar: View {
    var member: TeamMember
    var size: CGFloat

    var body: some View {
        Group {
            if let path = member.avatarPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let asset = member.avatarAsset,
                      let url = Bundle.module.url(forResource: asset, withExtension: "png", subdirectory: "Avatars"),
                      let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: member.role.symbol)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(roleColor, in: Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }

    private var roleColor: Color {
        switch member.role {
        case .chiefOfStaff: return .indigo
        case .developer: return .blue
        case .itSpecialist: return .teal
        case .peoplePartner: return .pink
        case .counsel: return .purple
        case .researcher: return .orange
        case .strategist: return .red
        case .designer: return .gray
        case .operations: return .green
        case .familyDoctor: return .mint
        }
    }
}

private struct ChatView: View {
    @EnvironmentObject private var store: AuraStore
    var member: TeamMember

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TeamAvatar(member: member, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name).font(.headline)
                    Text(member.role.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.contextStatus.detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { store.conversationMode(for: member) },
                    set: { store.setConversationMode($0, for: member) }
                )) {
                    ForEach(ConversationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 154)
                Button { store.memoryMember = member } label: { Image(systemName: "brain.head.profile") }
                    .help(auraText("Character memory", "캐릭터별 기억"))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.bar)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if store.messages.isEmpty {
                            VStack(spacing: 12) {
                                TeamAvatar(member: member, size: 76)
                                Text(member.name).font(.title2.weight(.semibold))
                                Text(member.tagline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 72)
                        }
                        ForEach(store.messages) { message in
                            MessageBubble(message: message, member: member)
                                .id(message.id)
                        }
                        if store.isWorking(for: member) {
                            WorkingActivityView(member: member, events: store.harnessEvents, agentMode: store.settings.agentModeEnabled || !store.harnessEvents.isEmpty)
                            .id("working")
                        }
                    }
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
                .onChange(of: store.messages.count) { _, _ in
                    if let message = store.messages.last { proxy.scrollTo(message.id, anchor: .bottom) }
                }
                .onChange(of: store.isWorking) { _, working in
                    if working, store.isWorking(for: member) { proxy.scrollTo("working", anchor: .bottom) }
                }
                .onChange(of: store.harnessEvents.count) { _, _ in
                    if store.isWorking(for: member) { proxy.scrollTo("working", anchor: .bottom) }
                }
            }

            VStack(spacing: 8) {
                if !store.pendingAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(store.pendingAttachments) { attachment in
                                AttachmentChip(attachment: attachment) {
                                    store.removePendingAttachment(attachment)
                                }
                            }
                        }
                    }
                }
                HStack(alignment: .center, spacing: 9) {
                    Button { store.chooseAttachments() } label: {
                        Image(systemName: "paperclip")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isWorking(for: member) || store.isExtractingAttachments)
                    .help(auraText("Attach image, PDF, Word, Excel, or text", "이미지, PDF, Word, Excel 또는 텍스트 첨부"))

                    TextField(auraText("Message \(member.name)", "\(member.name)에게 메시지"), text: $store.draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...10)
                        .frame(minHeight: 28, alignment: .center)
                        .onSubmit { store.beginSend() }

                    if store.isExtractingAttachments {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { store.beginSend() } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title2)
                        }
                        .buttonStyle(.plain)
                        .disabled((store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.pendingAttachments.isEmpty) || store.isWorking(for: member))
                        .help(auraText("Send", "보내기"))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
    }
}

private struct WorkingActivityView: View {
    let member: TeamMember
    let events: [AgentHarnessEvent]
    let agentMode: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TeamAvatar(member: member, size: 25)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(agentMode ? auraText("Working through the task...", "작업 진행 중...") : auraText("Thinking...", "생각 중..."))
                        .foregroundStyle(.secondary)
                }
                if let event = events.last {
                    Text(event.title)
                        .font(.caption.weight(.medium))
                    Text(event.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }
}

private struct AttachmentChip: View {
    @EnvironmentObject private var store: AuraStore
    var attachment: ChatAttachment
    var remove: (() -> Void)?

    var body: some View {
        Group {
            if remove == nil, existingFileURL != nil {
                Button { store.previewAttachment = attachment } label: { chipContent }
                    .buttonStyle(.plain)
                    .help(auraText("Preview file", "파일 미리보기"))
            } else {
                chipContent
            }
        }
    }

    private var existingFileURL: URL? {
        let url = URL(fileURLWithPath: attachment.storedPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var chipContent: some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.kind.contains("Image") ? "photo" : "doc")
            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.fileName).lineLimit(1)
                Text(attachment.kind).font(.caption2).foregroundStyle(.secondary)
            }
            if let remove {
                Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(auraText("Remove attachment", "첨부 삭제"))
            }
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: 260)
    }
}

private struct ArtifactPreviewPane: View {
    @EnvironmentObject private var store: AuraStore
    let attachment: ChatAttachment

    private var fileURL: URL { URL(fileURLWithPath: attachment.storedPath) }
    private var isHTML: Bool { ["html", "htm"].contains(fileURL.pathExtension.lowercased()) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: previewSymbol)
                    .foregroundStyle(AuraTheme.accent)
                Text(attachment.fileName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button { store.export(attachment) } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(.plain)
                    .help(auraText("Export a copy", "사본 내보내기"))
                ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.plain)
                    .help(auraText("Share, including Messages", "공유하기 및 메시지"))
                Button { store.previewAttachment = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .help(auraText("Close preview", "미리보기 닫기"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.bar)

            Group {
                if isHTML {
                    HTMLFilePreview(url: fileURL)
                } else {
                    QuickLookFilePreview(url: fileURL)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var previewSymbol: String {
        switch fileURL.pathExtension.lowercased() {
        case "xlsx", "csv": return "tablecells"
        case "pptx": return "rectangle.on.rectangle.angled"
        case "docx", "rtf": return "doc.richtext"
        case "html", "htm": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}

private struct QuickLookFilePreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = url as NSURL
        view.autostarts = true
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
    }
}

private struct HTMLFilePreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.setValue(false, forKey: "drawsBackground")
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard view.url != url else { return }
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}

private struct MessageBubble: View {
    var message: ConversationMessage
    var member: TeamMember

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if message.role == .user { Spacer(minLength: 50) }
            if message.role == .assistant { TeamAvatar(member: member, size: 28) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
                Text(message.role == .user ? auraText("You", "나") : message.role == .assistant ? member.name : auraText("Aura tool", "Aura 도구"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Group {
                    if message.role == .assistant {
                        MarkdownMessageView(content: message.content)
                            .padding(.top, 1)
                    } else {
                        Text(message.content)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(AuraTheme.userBubble, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .textSelection(.enabled)
                if let attachments = message.attachments, !attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(attachments) { AttachmentChip(attachment: $0, remove: nil) }
                    }
                }
            }
            if message.role != .user { Spacer() }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct MarkdownMessageView: View {
    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(items: [String], ordered: Bool)
        case code(String)
        case divider
    }

    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(level == 1 ? .title3.weight(.bold) : level == 2 ? .headline : .body.weight(.semibold))
                .padding(.top, level == 1 ? 4 : 1)
        case .paragraph(let text):
            inlineText(text)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let items, let ordered):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .foregroundStyle(.secondary)
                            .frame(width: ordered ? 20 : 10, alignment: .trailing)
                        inlineText(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
        case .divider:
            Divider().padding(.vertical, 3)
        }
    }

    private var blocks: [Block] {
        let lines = content.components(separatedBy: .newlines)
        var result: [Block] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            if trimmed.hasPrefix("```") {
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                result.append(.code(code.joined(separator: "\n")))
                continue
            }
            if isDivider(trimmed) {
                result.append(.divider)
                index += 1
                continue
            }
            if let heading = heading(from: trimmed) {
                result.append(heading)
                index += 1
                continue
            }
            if let currentListItem = listItem(from: trimmed) {
                var items = [currentListItem.text]
                let ordered = currentListItem.ordered
                index += 1
                while index < lines.count, let next = listItem(from: lines[index].trimmingCharacters(in: .whitespaces)), next.ordered == ordered {
                    items.append(next.text)
                    index += 1
                }
                result.append(.bullet(items: items, ordered: ordered))
                continue
            }

            var paragraph = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                guard !next.isEmpty, !next.hasPrefix("```"), !isDivider(next), heading(from: next) == nil, listItem(from: next) == nil else { break }
                paragraph.append(next)
                index += 1
            }
            result.append(.paragraph(paragraph.joined(separator: "\n")))
        }
        return result
    }

    private func inlineText(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: source, options: options) {
            return Text(attributed)
        }
        return Text(source)
    }

    private func heading(from line: String) -> Block? {
        let level = line.prefix { $0 == "#" }.count
        guard level > 0, level <= 6 else { return nil }
        let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : .heading(level: level, text: text)
    }

    private func listItem(from line: String) -> (text: String, ordered: Bool)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return (String(line.dropFirst(2)), false)
        }
        guard let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) else { return nil }
        return (String(line[range.upperBound...]), true)
    }

    private func isDivider(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return Set(compact).count == 1 && ["-", "*", "_"].contains(compact.first.map(String.init) ?? "")
    }
}

private struct AddMemberSheet: View {
    @EnvironmentObject private var store: AuraStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(auraText("Add a teammate", "친구 추가")).font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(auraText("Close", "닫기"))
            }
            Text(auraText("Start from a role, then adjust its identity and instructions in Settings.", "역할을 선택한 뒤 설정에서 이름과 지침을 조정하세요."))
                .foregroundStyle(.secondary)
            ForEach(TeamRole.allCases) { role in
                Button {
                    store.createMember(role: role)
                    dismiss()
                } label: {
                    Label(role.title, systemImage: role.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 390)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AuraStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = "Connection"
    @State private var editingMember: TeamMember?
    @State private var memoryMember: TeamMember?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(auraText("Settings", "설정"))
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(auraText("Close settings", "설정 닫기"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            TabView(selection: $selectedTab) {
                connectionTab.tabItem { Label(auraText("Connection", "연결"), systemImage: "cpu") }.tag("Connection")
                privacyTab.tabItem { Label(auraText("Privacy", "개인정보"), systemImage: "hand.raised") }.tag("Privacy")
                teamTab.tabItem { Label(auraText("Friends", "친구"), systemImage: "person.3") }.tag("Team")
                skillsTab.tabItem { Label(auraText("Skills", "기술"), systemImage: "wand.and.stars") }.tag("Skills")
                harnessTab.tabItem { Label(auraText("Tools", "도구"), systemImage: "hammer") }.tag("Harness")
            }
            .padding(18)
        }
        .frame(width: 720, height: 600)
        .sheet(item: $editingMember) { member in
            FriendEditor(member: member)
        }
        .sheet(item: $memoryMember) { member in
            MemoryVaultSheet(title: auraText("What \(member.name) remembers", "\(member.name)이 기억하는 내용"), vault: store.memberMemoryVault(member))
        }
        .onDisappear { store.saveSettings() }
    }

    private var connectionTab: some View {
        Form {
            Picker(auraText("Provider", "제공자"), selection: $store.settings.provider.kind) {
                ForEach(ProviderKind.allCases) { Text($0.label).tag($0) }
            }
            TextField(auraText("Server URL", "서버 URL"), text: $store.settings.provider.baseURL)
            TextField(auraText("Model", "모델"), text: $store.settings.provider.model)
            if store.settings.provider.kind.isCloud {
                SecureField(auraText("API key", "API 키"), text: $store.settings.provider.apiKey)
            }
            if store.settings.provider.kind == .local {
                Text(auraText("Use your own llama.cpp server or keep Aura pointed at the local server configured during onboarding.", "직접 실행한 llama.cpp 서버를 사용하거나 온보딩에서 설정한 로컬 서버 연결을 유지하세요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var privacyTab: some View {
        Form {
            Toggle(auraText("Review before cloud requests", "클라우드 요청 전 검토"), isOn: $store.settings.privacy.enabled)
            Toggle(auraText("Emails", "이메일"), isOn: $store.settings.privacy.redactEmails)
            Toggle(auraText("Phone numbers", "전화번호"), isOn: $store.settings.privacy.redactPhones)
            Toggle(auraText("Card numbers", "카드 번호"), isOn: $store.settings.privacy.redactCards)
            Toggle(auraText("Likely API secrets", "추정 API 비밀값"), isOn: $store.settings.privacy.redactSecrets)
            Text(auraText("Aura redacts locally and shows a review sheet before sending a cloud request. The original values are restored only in the final response shown to you.", "Aura는 민감한 정보를 로컬에서 가린 뒤 클라우드 전송 전에 검토 화면을 보여줍니다. 원래 값은 화면에 표시되는 최종 답변에서만 복원됩니다."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var teamTab: some View {
        List {
            ForEach(store.members) { member in
                HStack {
                    Button { editingMember = member } label: { TeamAvatar(member: member, size: 30) }
                        .buttonStyle(.plain)
                        .help(auraText("Edit friend", "친구 편집"))
                    VStack(alignment: .leading) {
                        Text(member.name)
                        Text(member.role.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(auraText("Edit", "편집")) { editingMember = member }
                        .buttonStyle(.bordered)
                    Button(auraText("Memory", "기억")) { memoryMember = member }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var harnessTab: some View {
        Form {
            HStack {
                Text(store.settings.workspacePath.isEmpty ? auraText("No write folder selected", "저장 폴더가 선택되지 않았습니다") : store.settings.workspacePath)
                    .lineLimit(1)
                    .foregroundStyle(store.settings.workspacePath.isEmpty ? .secondary : .primary)
                Spacer()
                Button(auraText("Use Documents/AuraAi", "문서/AuraAiKR 사용")) { store.useDefaultWorkspace() }
                Button(auraText("Choose write folder", "저장 폴더 선택")) { store.chooseWorkspace() }
            }
            Section(auraText("Read-only folder access", "읽기 전용 폴더 접근")) {
                Button(auraText("Allow another folder", "다른 폴더 허용")) { store.chooseAdditionalFolder() }
                if store.settings.authorizedFolderPaths.isEmpty {
                    Text(auraText("No extra folders are available to agents.", "추가로 허용된 폴더가 없습니다."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.settings.authorizedFolderPaths, id: \.self) { path in
                        HStack {
                            Text(path).lineLimit(1)
                            Spacer()
                            Button(auraText("Remove", "삭제"), role: .destructive) { store.revokeFolderAccess(path) }
                        }
                    }
                }
            }
            Text(auraText("Folder inspection is read-only. Aura asks before selecting extra folders, writing files, running commands, or controlling the Mac.", "폴더 확인은 읽기 전용입니다. 추가 폴더 선택, 파일 쓰기, 명령 실행, Mac 제어 전에는 Aura가 승인을 요청합니다."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var skillsTab: some View {
        List {
            Section {
                Text(auraText("Skills are the document-making capabilities available to the whole team. A friend can only use a skill when it is enabled here and in that friend's editor.", "기술은 팀 전체에 제공되는 문서 생성 기능입니다. 여기와 각 친구 편집 화면에서 모두 켜져야 친구가 사용할 수 있습니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(AgentSkill.allCases) { skill in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: skill.symbol)
                            .frame(width: 22)
                            .foregroundStyle(AuraTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(skill.title).font(.headline)
                            Text(skill.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Toggle("", isOn: Binding(
                            get: { store.skillSettings.isEnabled(skill) },
                            set: { store.setSkillEnabled($0, for: skill) }
                        ))
                        .labelsHidden()
                    }
                    Label(auraText("Tool: \(skill.toolName)", "도구: \(skill.toolName)"), systemImage: "terminal")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 32)
                }
                .padding(.vertical, 6)
            }
        }
    }
}

private struct FriendEditor: View {
    @EnvironmentObject private var store: AuraStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TeamMember

    private let templateAssets = [
        "nova", "sage", "rio", "luna", "max", "gilleon", "neir", "european-woman",
        "nova-ko", "sage-ko", "rio-ko", "luna-ko", "max-ko", "gilleon-ko", "neir-ko", "korean-woman"
    ]

    init(member: TeamMember) { _draft = State(initialValue: member) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(auraText("Edit friend", "친구 편집"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain)
                    .help(auraText("Close", "닫기"))
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 16) {
                        TeamAvatar(member: draft, size: 72)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(draft.name).font(.headline)
                            Button {
                                if let path = store.importAvatar(for: draft) {
                                    draft.avatarPath = path
                                }
                            } label: {
                                Label(auraText("Upload your own photo", "내 사진 업로드"), systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(auraText("Template photo", "기본 사진"))
                            .font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(54), spacing: 10), count: 8), spacing: 10) {
                            ForEach(templateAssets, id: \.self) { asset in
                                Button {
                                    draft.avatarAsset = asset
                                    draft.avatarPath = nil
                                } label: {
                                    templateImage(asset)
                                        .overlay(alignment: .bottomTrailing) {
                                            if draft.avatarPath == nil && draft.avatarAsset == asset {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.white, AuraTheme.accent)
                                                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .help(asset)
                            }
                        }
                    }

                    Form {
                        TextField(auraText("Name", "이름"), text: $draft.name)
                        Picker(auraText("Specialty", "전문 분야"), selection: $draft.role) {
                            ForEach(TeamRole.allCases) { role in Text(role.title).tag(role) }
                        }
                        TextField(auraText("Tagline", "한 줄 소개"), text: $draft.tagline)
                    }
                    .formStyle(.grouped)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(auraText("Personality", "성격과 지침"))
                            .font(.headline)
                        Text(auraText("Describe how this friend thinks, speaks, and helps you.", "이 친구가 생각하고 말하며 도움을 주는 방식을 적어주세요."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $draft.customInstructions)
                            .font(.body)
                            .frame(minHeight: 130)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(auraText("Skills", "기술"))
                            .font(.headline)
                        Text(auraText("This friend can use only the skills enabled here and in Settings. File creation still requires your approval.", "이 친구는 여기와 설정에서 모두 켠 기술만 사용할 수 있습니다. 파일 생성 전에는 여전히 승인을 요청합니다."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(AgentSkill.allCases) { skill in
                            Toggle(isOn: Binding(
                                get: { draft.isSkillEnabled(skill) },
                                set: { draft.setSkillEnabled($0, for: skill) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(skill.title, systemImage: skill.symbol)
                                    Text(auraText("Tool: \(skill.toolName)", "도구: \(skill.toolName)"))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            Divider()
            HStack {
                Button(auraText("Cancel", "취소")) { dismiss() }
                Spacer()
                Button(auraText("Save friend", "친구 저장")) {
                    store.saveMember(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 680, height: 650)
    }

    @ViewBuilder
    private func templateImage(_ asset: String) -> some View {
        if let url = Bundle.module.url(forResource: asset, withExtension: "png", subdirectory: "Avatars"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 46))
                .frame(width: 52, height: 52)
        }
    }
}

private struct MemoryVaultSheet: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    let vault: MarkdownMemoryVault
    @State private var notes: [MarkdownMemoryNote]
    @State private var draft = ""
    @State private var retention: MemoryRetention = .longTerm

    init(title: String, vault: MarkdownMemoryVault) {
        self.title = title
        self.vault = vault
        _notes = State(initialValue: vault.list())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.semibold))
            Text(auraText("Long-term notes stay until you delete them. Expiring notes disappear automatically after their selected time.", "장기 기억은 직접 삭제할 때까지 유지됩니다. 만료 기억은 선택한 시간이 지나면 자동으로 사라집니다."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if notes.isEmpty {
                ContentUnavailableView(auraText("No memories yet", "아직 기억이 없습니다"), systemImage: "brain.head.profile")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(notes, id: \.slug) { note in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.body)
                                    .lineLimit(3)
                                Text(retentionLabel(note))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                vault.delete(note)
                                reload()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .help(auraText("Delete memory", "기억 삭제"))
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 76)
                    .padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                HStack {
                    Picker(auraText("Retention", "기억 기간"), selection: $retention) {
                        ForEach(MemoryRetention.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Button(auraText("Remember", "기억하기")) {
                        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        _ = vault.save(body: draft, retention: retention)
                        draft = ""
                        reload()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            HStack {
                Button(auraText("Open Markdown vault", "Markdown 보관함 열기")) { NSWorkspace.shared.open(vault.url) }
                Spacer()
                Button(auraText("Close", "닫기")) { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 660, height: 560)
    }

    private func reload() { notes = vault.list() }

    private func retentionLabel(_ note: MarkdownMemoryNote) -> String {
        guard let expiresAt = note.expiresAt else { return auraText("Long-term memory", "장기 기억") }
        return auraText("Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))", "\(expiresAt.formatted(date: .abbreviated, time: .omitted)) 만료")
    }
}

private struct PrivacyReviewSheet: View {
    @EnvironmentObject private var store: AuraStore
    var review: PrivacyReview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(auraText("Review privacy replacements", "개인정보 가림 검토"), systemImage: "hand.raised.fill")
                .font(.title2.weight(.semibold))
            Text(auraText("This is the redacted version that will be sent to your cloud provider. Nothing is sent until you approve.", "클라우드 제공자에게 전송될 가림 처리본입니다. 승인하기 전에는 아무것도 전송되지 않습니다."))
                .foregroundStyle(.secondary)
            List(review.matches) { match in
                HStack {
                    Text(match.category.capitalized).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
                    Text(match.original).lineLimit(1)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(match.placeholder).fontDesign(.monospaced)
                }
            }
            ScrollView {
                Text(review.redacted).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            HStack {
                Button(auraText("Cancel", "취소"), role: .cancel) { store.cancelPrivacy() }
                Spacer()
                Button(auraText("Send redacted", "가림 처리본 보내기")) { store.approvePrivacy() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 650, height: 500)
    }
}

private struct AgentApprovalSheet: View {
    @EnvironmentObject private var store: AuraStore
    var approval: AgentApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(approval.kind.title, systemImage: "exclamationmark.shield.fill")
                .font(.title2.weight(.semibold))
            Text(approval.title).font(.headline)
            ScrollView {
                Text(approval.detail)
                    .textSelection(.enabled)
                    .fontDesign(.monospaced)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            HStack {
                Button(auraText("Decline", "거절"), role: .cancel) { store.resolveApproval(false) }
                Spacer()
                Button(auraText("Allow once", "한 번 허용")) { store.resolveApproval(true) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 580, height: 360)
        .interactiveDismissDisabled()
    }
}
