import AppKit
import PDFKit
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
                Text("Aura AI").font(.headline)
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
                if step > 0 { Button(auraText("Back", "뒤로")) { step -= 1 }.buttonStyle(ClickCursorBorderedButtonStyle()) }
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
                .buttonStyle(ClickCursorProminentButtonStyle())
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
                .onChange(of: store.settings.provider.kind) { _, kind in store.applyProviderPreset(kind) }
                GroupBox {
                    ProviderConnectionFields()
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
                        .buttonStyle(ClickCursorBorderedButtonStyle())
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

private struct ProviderConnectionFields: View {
    @EnvironmentObject private var store: AuraStore

    private var provider: ProviderKind { store.settings.provider.kind }
    private var models: [String] {
        let options = provider.modelOptions
        let current = store.settings.provider.model
        return options.contains(current) || current.isEmpty ? options : options + [current]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !models.isEmpty {
                Picker(auraText("Suggested model", "추천 모델"), selection: $store.settings.provider.model) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
            }
            TextField(auraText("Model ID", "모델 ID"), text: $store.settings.provider.model)
            TextField(auraText("API base URL", "API 기본 URL"), text: $store.settings.provider.baseURL)
            if provider.isCloud {
                SecureField(auraText("API key", "API 키"), text: $store.settings.provider.apiKey)
            } else {
                Text(auraText("Use your own llama.cpp server or keep Aura pointed at the local multimodal server configured during onboarding.", "직접 실행한 llama.cpp 서버를 사용하거나 온보딩에서 설정한 로컬 멀티모달 서버 연결을 유지하세요."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AuraWorkspaceView: View {
    @EnvironmentObject private var store: AuraStore
    @State private var isShowingAddMember = false
    @State private var isSidebarVisible = true

    var body: some View {
        Group {
            if let member = store.selectedMember {
                AdaptiveWorkspaceSplit(
                    showsSidebar: $isSidebarVisible,
                    sidebar: FriendsSidebar(isShowingAddMember: $isShowingAddMember)
                        .environmentObject(store),
                    conversation: ChatView(member: member)
                        .environmentObject(store),
                    preview: store.previewAttachment.map {
                        AnyView(ArtifactPreviewPane(attachment: $0).environmentObject(store))
                    }
                )
            } else {
                ContentUnavailableView(auraText("Choose a teammate", "친구를 선택하세요"), systemImage: "person.2")
            }
        }
        .background(WindowTitlebarSidebarToggle(isSidebarVisible: $isSidebarVisible))
        .overlay { WindowResizeCursorOverlay() }
        .sheet(isPresented: $isShowingAddMember) { AddMemberSheet() }
        .sheet(isPresented: $store.isShowingSettings) { SettingsView() }
        .sheet(isPresented: $store.isShowingGlobalMemory) {
            MemoryVaultSheet(title: auraText("Global memory", "공통 기억"), vault: store.globalMemoryVault())
        }
        .sheet(item: $store.memoryMember) { member in
            MemoryVaultSheet(title: auraText("What \(member.name) remembers", "\(koreanSubject(member.name)) 기억하는 내용"), vault: store.memberMemoryVault(member))
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

/// This is intentionally part of the workspace overlay instead of a titlebar
/// accessory. Hidden-titlebar windows do not reliably render accessories, and
/// the control must remain present after the navigation pane is hidden.
private struct WorkspaceSidebarToggle: View {
    @Binding var isSidebarVisible: Bool

    var body: some View {
        Button { isSidebarVisible.toggle() } label: {
            Image(systemName: isSidebarVisible ? "sidebar.left" : "sidebar.right")
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(ClickCursorPlainButtonStyle())
        .focusable(false)
        .focusEffectDisabled()
        .help(isSidebarVisible ? auraText("Hide sidebar", "사이드바 숨기기") : auraText("Show sidebar", "사이드바 보이기"))
        .accessibilityLabel(isSidebarVisible ? auraText("Hide sidebar", "사이드바 숨기기") : auraText("Show sidebar", "사이드바 보이기"))
    }
}

/// Places the navigation control in the real titlebar, immediately after the
/// traffic lights. Unlike a SwiftUI toolbar item, it has no effect on pane
/// layout and remains visible when the navigation pane is collapsed.
private struct WindowTitlebarSidebarToggle: NSViewRepresentable {
    @Binding var isSidebarVisible: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TitlebarAnchorView {
        let anchor = TitlebarAnchorView()
        anchor.onWindowAvailable = { [weak coordinator = context.coordinator] window in
            coordinator?.install(in: window)
        }
        return anchor
    }

    func updateNSView(_ anchor: TitlebarAnchorView, context: Context) {
        context.coordinator.sidebarVisibility = $isSidebarVisible
        if let window = anchor.window { context.coordinator.install(in: window) }
        context.coordinator.render()
    }

    final class Coordinator: NSObject {
        var sidebarVisibility: Binding<Bool>?
        private weak var window: NSWindow?
        private weak var titlebarView: NSView?
        private weak var workspaceSplitView: WorkspaceSplitView?
        private let button = PointingHandButton()
        private let menuTitlebarMaterial = NSVisualEffectView()
        private var constraints: [NSLayoutConstraint] = []
        private var dividerExtensions: [NSView] = []
        private var splitObserver: NSObjectProtocol?

        deinit {
            if let splitObserver { NotificationCenter.default.removeObserver(splitObserver) }
        }

        override init() {
            super.init()
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(toggleSidebar)
            button.toolTip = auraText("Hide sidebar", "사이드바 숨기기")
            button.setAccessibilityLabel(button.toolTip)
            menuTitlebarMaterial.material = .sidebar
            menuTitlebarMaterial.blendingMode = .behindWindow
            menuTitlebarMaterial.state = .active
        }

        func install(in window: NSWindow) {
            guard let zoomButton = window.standardWindowButton(.zoomButton),
                  let titlebarView = zoomButton.superview else { return }
            self.window = window
            self.titlebarView = titlebarView

            if menuTitlebarMaterial.superview !== titlebarView {
                menuTitlebarMaterial.removeFromSuperview()
                titlebarView.addSubview(menuTitlebarMaterial, positioned: .below, relativeTo: nil)
            }

            if button.superview !== titlebarView {
                NSLayoutConstraint.deactivate(constraints)
                constraints = []
                button.removeFromSuperview()
                button.translatesAutoresizingMaskIntoConstraints = false
                titlebarView.addSubview(button)
                constraints = [
                    button.leadingAnchor.constraint(equalTo: zoomButton.trailingAnchor, constant: 8),
                    button.centerYAnchor.constraint(equalTo: zoomButton.centerYAnchor),
                    button.widthAnchor.constraint(equalToConstant: 28),
                    button.heightAnchor.constraint(equalToConstant: 24)
                ]
                NSLayoutConstraint.activate(constraints)
            }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.observeDividerPositions(in: window)
            }
        }

        func render() {
            let isVisible = sidebarVisibility?.wrappedValue ?? true
            button.image = NSImage(systemSymbolName: isVisible ? "sidebar.left" : "sidebar.right", accessibilityDescription: nil)
            button.toolTip = isVisible ? auraText("Hide sidebar", "사이드바 숨기기") : auraText("Show sidebar", "사이드바 보이기")
            button.setAccessibilityLabel(button.toolTip)
        }

        @objc private func toggleSidebar() {
            sidebarVisibility?.wrappedValue.toggle()
        }

        private func observeDividerPositions(in window: NSWindow) {
            guard let splitView = findWorkspaceSplit(in: window.contentView) else { return }
            if workspaceSplitView !== splitView {
                if let splitObserver { NotificationCenter.default.removeObserver(splitObserver) }
                workspaceSplitView = splitView
                splitObserver = NotificationCenter.default.addObserver(
                    forName: NSSplitView.didResizeSubviewsNotification,
                    object: splitView,
                    queue: .main
                ) { [weak self] _ in
                    self?.syncDividerExtensions()
                }
            }
            syncDividerExtensions()
        }

        private func syncDividerExtensions() {
            guard let splitView = workspaceSplitView, let titlebarView else { return }
            let panes = splitView.arrangedSubviews.dropLast()
            let showsSidebar = sidebarVisibility?.wrappedValue == true
            if showsSidebar, let sidebarPane = splitView.arrangedSubviews.first {
                let point = splitView.convert(NSPoint(x: sidebarPane.frame.maxX, y: 0), to: titlebarView)
                menuTitlebarMaterial.isHidden = false
                menuTitlebarMaterial.frame = NSRect(x: 0, y: 0, width: floor(point.x), height: titlebarView.bounds.height)
            } else {
                menuTitlebarMaterial.isHidden = true
            }
            while dividerExtensions.count > panes.count {
                dividerExtensions.removeLast().removeFromSuperview()
            }
            while dividerExtensions.count < panes.count {
                let extensionView = NSView()
                extensionView.wantsLayer = true
                extensionView.layer?.backgroundColor = NSColor(calibratedWhite: 0.32, alpha: 1).cgColor
                titlebarView.addSubview(extensionView, positioned: .above, relativeTo: menuTitlebarMaterial)
                dividerExtensions.append(extensionView)
            }
            for (extensionView, pane) in zip(dividerExtensions, panes) {
                let point = splitView.convert(NSPoint(x: pane.frame.maxX, y: 0), to: titlebarView)
                extensionView.frame = NSRect(x: floor(point.x), y: 0, width: 1, height: titlebarView.bounds.height)
            }
        }

        private func findWorkspaceSplit(in view: NSView?) -> WorkspaceSplitView? {
            guard let view else { return nil }
            if let splitView = view as? WorkspaceSplitView { return splitView }
            return view.subviews.lazy.compactMap { self.findWorkspaceSplit(in: $0) }.first
        }
    }
}

private final class TitlebarAnchorView: NSView {
    var onWindowAvailable: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindowAvailable?(window) }
    }
}

private final class PointingHandButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

struct ClickCursorDefaultButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
            .clickCursor()
    }
}

private struct ClickCursorPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
            .clickCursor()
    }
}

private struct ClickCursorBorderedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white.opacity(0.16)))
            .opacity(configuration.isPressed ? 0.65 : 1)
            .clickCursor()
    }
}

private struct ClickCursorProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AuraTheme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .clickCursor()
    }
}

private struct ClickCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { isHovering in
            if isHovering { NSCursor.pointingHand.set() }
            else { NSCursor.arrow.set() }
        }
    }
}

private extension View {
    func clickCursor() -> some View { modifier(ClickCursorModifier()) }
}

private struct SidebarMaterialBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// One plain split view owns the three pane surfaces. Structural changes always
/// rebuild the arranged subviews so a collapsed navigation pane cannot retain
/// stale width in the main layout.
private struct AdaptiveWorkspaceSplit: NSViewRepresentable {
    @Binding var showsSidebar: Bool
    let sidebar: AnyView
    let conversation: AnyView
    let preview: AnyView?

    init<Sidebar: View, Conversation: View>(
        showsSidebar: Binding<Bool>,
        sidebar: Sidebar,
        conversation: Conversation,
        preview: AnyView?
    ) {
        self._showsSidebar = showsSidebar
        self.sidebar = AnyView(sidebar)
        self.conversation = AnyView(conversation)
        self.preview = preview
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = WorkspaceSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        context.coordinator.install(
            in: splitView,
            sidebar: sidebar,
            conversation: conversation,
            preview: preview,
            showsSidebar: showsSidebar,
            sidebarVisibility: $showsSidebar
        )
        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.update(
            in: splitView,
            sidebar: sidebar,
            conversation: conversation,
            preview: preview,
            showsSidebar: showsSidebar,
            sidebarVisibility: $showsSidebar
        )
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        private let sidebarMinimum: CGFloat = 280
        private let defaultSidebarWidth: CGFloat = 300
        private var sidebarHost: NSHostingController<AnyView>?
        private var conversationHost: NSHostingController<AnyView>?
        private var previewHost: NSHostingController<AnyView>?
        private var currentShowsSidebar: Bool?
        private var currentHasPreview: Bool?
        private var sidebarVisibility: Binding<Bool>?

        func install(
            in splitView: NSSplitView,
            sidebar: AnyView,
            conversation: AnyView,
            preview: AnyView?,
            showsSidebar: Bool,
            sidebarVisibility: Binding<Bool>
        ) {
            splitView.delegate = self
            self.sidebarVisibility = sidebarVisibility

            let sidebarHost = NSHostingController(rootView: sidebar)
            let conversationHost = NSHostingController(rootView: conversation)
            self.sidebarHost = sidebarHost
            self.conversationHost = conversationHost
            if let preview { self.previewHost = NSHostingController(rootView: preview) }
            rebuild(in: splitView, showsSidebar: showsSidebar, hasPreview: preview != nil)
        }

        func update(
            in splitView: NSSplitView,
            sidebar: AnyView,
            conversation: AnyView,
            preview: AnyView?,
            showsSidebar: Bool,
            sidebarVisibility: Binding<Bool>
        ) {
            self.sidebarVisibility = sidebarVisibility
            sidebarHost?.rootView = sidebar
            conversationHost?.rootView = conversation

            switch (previewHost, preview) {
            case let (host?, preview?): host.rootView = preview
            case (nil, let preview?): previewHost = NSHostingController(rootView: preview)
            case (_, nil): previewHost = nil
            }

            let hasPreview = preview != nil
            if currentShowsSidebar != showsSidebar || currentHasPreview != hasPreview {
                rebuild(in: splitView, showsSidebar: showsSidebar, hasPreview: hasPreview)
            }
        }

        private func rebuild(in splitView: NSSplitView, showsSidebar: Bool, hasPreview: Bool) {
            splitView.arrangedSubviews.forEach {
                splitView.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
            if showsSidebar, let sidebarView = sidebarHost?.view {
                splitView.addArrangedSubview(sidebarView)
            }
            if let conversationView = conversationHost?.view {
                splitView.addArrangedSubview(conversationView)
            }
            if hasPreview, let previewView = previewHost?.view {
                splitView.addArrangedSubview(previewView)
            }
            currentShowsSidebar = showsSidebar
            currentHasPreview = hasPreview
            (splitView as? WorkspaceSplitView)?.fixedDividerIndices = showsSidebar ? [0] : []
            splitView.adjustSubviews()
            DispatchQueue.main.async { [weak splitView] in
                guard let splitView else { return }
                if showsSidebar, splitView.arrangedSubviews.count >= 2 {
                    splitView.setPosition(self.defaultSidebarWidth, ofDividerAt: 0)
                }
                if hasPreview, splitView.arrangedSubviews.count >= 2 {
                    let divider = splitView.dividerThickness
                    let contentStart = showsSidebar ? self.defaultSidebarWidth + divider : 0
                    let remaining = max(680, splitView.bounds.width - contentStart - divider)
                    splitView.setPosition(contentStart + remaining * 0.62, ofDividerAt: splitView.arrangedSubviews.count - 2)
                }
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0, currentShowsSidebar == true else { return proposed }
            return defaultSidebarWidth
        }

        func splitView(_ splitView: NSSplitView, constrainSplitPosition proposed: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0, currentShowsSidebar == true else { return proposed }
            return defaultSidebarWidth
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0, currentShowsSidebar == true else { return proposed }
            return defaultSidebarWidth
        }

        func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview subview: NSView) -> Bool {
            subview !== sidebarHost?.view
        }
    }
}

private final class WorkspaceSplitView: NSSplitView {
    private var dividerTrackingAreas: [NSTrackingArea] = []
    var fixedDividerIndices: Set<Int> = [] {
        didSet {
            if oldValue != fixedDividerIndices {
                hoveredDividerIndex = nil
                needsDisplay = true
                window?.invalidateCursorRects(for: self)
            }
        }
    }
    private var hoveredDividerIndex: Int? {
        didSet { if oldValue != hoveredDividerIndex { needsDisplay = true } }
    }

    override var dividerColor: NSColor {
        NSColor(calibratedWhite: 0.32, alpha: 1)
    }

    override var dividerThickness: CGFloat { 1 }

    override func drawDivider(in rect: NSRect) {
        if let hoveredDividerIndex,
           dividerRect(for: hoveredDividerIndex).intersects(rect) {
            NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
            rect.insetBy(dx: -2, dy: 0).fill()
            NSColor.controlAccentColor.withAlphaComponent(0.72).setFill()
            rect.fill()
            return
        }
        dividerColor.setFill()
        rect.fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if dividerHitAreas.contains(where: { $0.rect.contains(point) }) { return self }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        dividerHitAreas.forEach { addCursorRect($0.rect, cursor: .columnResize(directions: .all)) }
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let area = dividerHitAreas.first(where: { $0.rect.contains(point) }) {
            hoveredDividerIndex = area.index
            NSCursor.columnResize(directions: .all).set()
        } else {
            hoveredDividerIndex = nil
            super.cursorUpdate(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        dividerTrackingAreas.forEach(removeTrackingArea)
        dividerTrackingAreas = dividerHitAreas.map { hitArea in
            let trackingArea = NSTrackingArea(
                rect: hitArea.rect,
                options: [.activeAlways, .mouseEnteredAndExited, .cursorUpdate],
                owner: self,
                userInfo: ["dividerIndex": hitArea.index]
            )
            addTrackingArea(trackingArea)
            return trackingArea
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if let index = event.trackingArea?.userInfo?["dividerIndex"] as? Int {
            hoveredDividerIndex = index
            NSCursor.columnResize(directions: .all).set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredDividerIndex = nil
    }

    override func layout() {
        super.layout()
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    private var dividerHitAreas: [(index: Int, rect: NSRect)] {
        arrangedSubviews.dropLast().enumerated().compactMap { index, pane in
            guard !fixedDividerIndices.contains(index) else { return nil }
            return (index, NSRect(x: pane.frame.maxX - 4, y: bounds.minY, width: dividerThickness + 8, height: bounds.height))
        }
    }

    private func dividerRect(for index: Int) -> NSRect {
        guard arrangedSubviews.indices.contains(index) else { return .zero }
        let pane = arrangedSubviews[index]
        return NSRect(x: pane.frame.maxX, y: bounds.minY, width: dividerThickness, height: bounds.height)
    }
}

private struct WindowResizeCursorOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowResizeCursorView { WindowResizeCursorView() }
    func updateNSView(_ view: WindowResizeCursorView, context: Context) {}
}

private final class WindowResizeCursorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        super.resetCursorRects()
        let edge: CGFloat = 6
        let corner: CGFloat = 14

        addCursorRect(NSRect(x: 0, y: corner, width: edge, height: max(0, bounds.height - corner * 2)), cursor: .frameResize(position: .left, directions: .all))
        addCursorRect(NSRect(x: bounds.width - edge, y: corner, width: edge, height: max(0, bounds.height - corner * 2)), cursor: .frameResize(position: .right, directions: .all))
        addCursorRect(NSRect(x: corner, y: bounds.height - edge, width: max(0, bounds.width - corner * 2), height: edge), cursor: .frameResize(position: .top, directions: .all))
        addCursorRect(NSRect(x: corner, y: 0, width: max(0, bounds.width - corner * 2), height: edge), cursor: .frameResize(position: .bottom, directions: .all))

        addCursorRect(NSRect(x: 0, y: bounds.height - corner, width: corner, height: corner), cursor: .frameResize(position: .topLeft, directions: .all))
        addCursorRect(NSRect(x: bounds.width - corner, y: bounds.height - corner, width: corner, height: corner), cursor: .frameResize(position: .topRight, directions: .all))
        addCursorRect(NSRect(x: 0, y: 0, width: corner, height: corner), cursor: .frameResize(position: .bottomLeft, directions: .all))
        addCursorRect(NSRect(x: bounds.width - corner, y: 0, width: corner, height: corner), cursor: .frameResize(position: .bottomRight, directions: .all))
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }
}

private struct FriendsSidebar: View {
    @EnvironmentObject private var store: AuraStore
    @Binding var isShowingAddMember: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text("Aura AI")
                    .font(.headline)
                Spacer()
                Button { isShowingAddMember = true } label: { Image(systemName: "person.badge.plus") }
                    .buttonStyle(ClickCursorPlainButtonStyle())
                    .focusable(false)
                    .focusEffectDisabled()
                    .help(auraText("Add friend", "친구 추가"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 11)

            Text(auraText("Friends", "친구"))
                .font(.caption.weight(.semibold))
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
            Divider().overlay(.white.opacity(0.10))
            VStack(spacing: 1) {
                SidebarAction(title: auraText("Global memory", "공통 기억"), symbol: "brain.head.profile") { store.isShowingGlobalMemory = true }
                SidebarAction(title: auraText("Settings", "설정"), symbol: "gearshape") { store.isShowingSettings = true }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
        }
        .background(SidebarMaterialBackground())
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
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
        }
        .buttonStyle(ClickCursorPlainButtonStyle())
        .focusable(false)
        .focusEffectDisabled()
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
                Button { store.memoryMember = member } label: { Image(systemName: "brain.head.profile") }
                    .help(auraText("Character memory", "캐릭터별 기억"))
                    .buttonStyle(ClickCursorPlainButtonStyle())
                    .focusable(false)
                    .focusEffectDisabled()
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 14)
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
                        if store.isStreaming(for: member) {
                            MessageBubble(
                                message: ConversationMessage(role: .assistant, content: store.streamingResponse),
                                member: member
                            )
                            .id("streaming")
                        }
                        if store.isWorking(for: member) {
                            WorkingActivityView(member: member, events: store.harnessEvents)
                            .id("working")
                        }
                        Color.clear.frame(height: 1).id("chat-bottom")
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
                .onChange(of: store.streamingResponse) { _, _ in
                    if store.isStreaming(for: member) { proxy.scrollTo("streaming", anchor: .bottom) }
                }
                .onChange(of: member.id) { _, _ in
                    scrollToLatest(proxy)
                }
                .onAppear {
                    scrollToLatest(proxy)
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
                    .buttonStyle(ClickCursorPlainButtonStyle())
                    .focusable(false)
                    .focusEffectDisabled()
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
                        .buttonStyle(ClickCursorPlainButtonStyle())
                        .focusable(false)
                        .focusEffectDisabled()
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

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if let last = store.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            } else {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }
}

private struct WorkingActivityView: View {
    let member: TeamMember
    let events: [AgentHarnessEvent]

    private var steps: [AgentHarnessEvent] {
        events.filter { $0.kind != .inferring }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TeamAvatar(member: member, size: 25)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(auraText("Working through the task...", "작업 진행 중..."))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(steps) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: stepSymbol(for: event))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(stepColor(for: event))
                                .frame(width: 14, height: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(.caption.weight(.medium))
                                Text(event.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func stepSymbol(for event: AgentHarnessEvent) -> String {
        switch event.kind {
        case .received: return "circle"
        case .toolRequested: return "circle.dotted"
        case .observation, .completed: return "checkmark.circle.fill"
        case .denied: return "pause.circle"
        case .failed: return "exclamationmark.circle"
        case .inferring: return "circle"
        }
    }

    private func stepColor(for event: AgentHarnessEvent) -> Color {
        switch event.kind {
        case .failed: return .orange
        case .denied: return .secondary
        case .toolRequested: return AuraTheme.accent
        default: return .secondary
        }
    }
}

private struct AttachmentChip: View {
    @EnvironmentObject private var store: AuraStore
    var attachment: ChatAttachment
    var remove: (() -> Void)?

    var body: some View {
        if attachment.isImage, let url = existingFileURL {
            ImageAttachmentPreview(attachment: attachment, url: url, remove: remove)
        } else if remove == nil, existingFileURL != nil {
            Button { store.previewAttachment = attachment } label: { chipContent }
                .buttonStyle(ClickCursorPlainButtonStyle())
                .help(auraText("Preview file", "파일 미리보기"))
        } else {
            chipContent
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
                    .buttonStyle(ClickCursorPlainButtonStyle())
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

private struct ImageAttachmentPreview: View {
    @EnvironmentObject private var store: AuraStore
    let attachment: ChatAttachment
    let url: URL
    var remove: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            image
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture {
                    guard remove == nil else { return }
                    store.previewAttachment = attachment
                }
                .help(remove == nil ? auraText("Preview image", "이미지 미리보기") : attachment.fileName)

            if let remove {
                Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(ClickCursorPlainButtonStyle())
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .padding(7)
                    .help(auraText("Remove attachment", "첨부 삭제"))
            }
        }
        .accessibilityLabel(auraText("Image attachment: \(attachment.fileName)", "이미지 첨부: \(attachment.fileName)"))
    }

    @ViewBuilder
    private var image: some View {
        if let source = NSImage(contentsOf: url) {
            Image(nsImage: source)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 340, maxHeight: 280, alignment: .leading)
        } else {
            Label(attachment.fileName, systemImage: "photo")
                .font(.caption)
                .padding(12)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ArtifactPreviewPane: View {
    @EnvironmentObject private var store: AuraStore
    let attachment: ChatAttachment

    private var fileURL: URL { URL(fileURLWithPath: attachment.storedPath) }
    private var isHTML: Bool { ["html", "htm"].contains(fileURL.pathExtension.lowercased()) }
    private var isMarkdown: Bool { ["md", "markdown", "mdown"].contains(fileURL.pathExtension.lowercased()) }
    private var isPresentation: Bool { ["ppt", "pptx"].contains(fileURL.pathExtension.lowercased()) }
    private var isImage: Bool { attachment.isImage }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: previewSymbol)
                    .foregroundStyle(AuraTheme.accent)
                Text(attachment.fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .allowsTightening(true)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(-1)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    previewButton("square.and.arrow.down", help: auraText("Export a copy", "사본 내보내기")) {
                        store.export(attachment)
                    }
                    ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(ClickCursorPlainButtonStyle())
                        .frame(width: 30, height: 30)
                        .focusable(false)
                        .focusEffectDisabled()
                        .help(auraText("Share, including Messages", "공유하기 및 메시지"))
                    previewButton("xmark", help: auraText("Close preview", "미리보기 닫기")) {
                        store.previewAttachment = nil
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(.bar)

            Group {
                if isHTML {
                    HTMLFilePreview(url: fileURL)
                } else if isMarkdown {
                    MarkdownFilePreview(url: fileURL)
                } else if isPresentation {
                    PresentationFilePreview(url: fileURL)
                } else if isImage {
                    ImageFilePreview(url: fileURL)
                } else {
                    QuickLookFilePreview(url: fileURL)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func previewButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(ClickCursorPlainButtonStyle())
            .frame(width: 30, height: 30)
            .focusable(false)
            .focusEffectDisabled()
            .help(help)
    }

    private var previewSymbol: String {
        switch fileURL.pathExtension.lowercased() {
        case "xlsx", "csv": return "tablecells"
        case "ppt", "pptx": return "rectangle.on.rectangle.angled"
        case "docx", "rtf": return "doc.richtext"
        case "html", "htm": return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown", "mdown": return "doc.text"
        default: return "doc"
        }
    }
}

private struct MarkdownFilePreview: View {
    let url: URL
    @State private var content: String?

    var body: some View {
        ScrollView {
            if let content {
                GFMMarkdownMessageView(content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
            } else {
                ContentUnavailableView(auraText("Markdown unavailable", "Markdown을 열 수 없습니다"), systemImage: "doc.text")
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .task(id: url) {
            content = try? String(contentsOf: url, encoding: .utf8)
        }
    }
}

private struct PresentationFilePreview: View {
    let url: URL
    @State private var renderedPDF: URL?
    @State private var slideIndex = 0
    @State private var slideCount = 0
    @State private var isRendering = true

    var body: some View {
        Group {
            if let renderedPDF {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Button { slideIndex = max(0, slideIndex - 1) } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(ClickCursorPlainButtonStyle())
                        .disabled(slideIndex == 0)
                        .help(auraText("Previous slide", "이전 슬라이드"))

                        Text(auraText("Slide \(slideIndex + 1) of \(max(1, slideCount))", "슬라이드 \(slideIndex + 1) / \(max(1, slideCount))"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(minWidth: 88)

                        Button { slideIndex = min(max(0, slideCount - 1), slideIndex + 1) } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(ClickCursorPlainButtonStyle())
                        .disabled(slideIndex >= max(0, slideCount - 1))
                        .help(auraText("Next slide", "다음 슬라이드"))

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.bar)

                    PresentationPDFView(url: renderedPDF, slideIndex: $slideIndex, slideCount: $slideCount)
                }
            } else if isRendering {
                ProgressView(auraText("Preparing slide preview…", "슬라이드 미리보기를 준비하는 중…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                QuickLookFilePreview(url: url)
            }
        }
        .task(id: url) {
            isRendering = true
            slideIndex = 0
            slideCount = 0
            renderedPDF = await Task.detached(priority: .utility) {
                PresentationPreviewRenderer.renderPDF(for: url)
            }.value
            isRendering = false
        }
    }
}

private struct PresentationPDFView: NSViewRepresentable {
    let url: URL
    @Binding var slideIndex: Int
    @Binding var slideCount: Int

    func makeCoordinator() -> Coordinator { Coordinator(slideIndex: $slideIndex, slideCount: $slideCount) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        context.coordinator.load(url, in: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.load(url, in: view)
        guard let document = view.document, let page = document.page(at: slideIndex), view.currentPage !== page else { return }
        view.go(to: page)
    }

    final class Coordinator {
        private var observedURL: URL?
        private var pageObserver: NSObjectProtocol?
        private var slideIndex: Binding<Int>
        private var slideCount: Binding<Int>

        init(slideIndex: Binding<Int>, slideCount: Binding<Int>) {
            self.slideIndex = slideIndex
            self.slideCount = slideCount
        }

        deinit {
            if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) }
        }

        func load(_ url: URL, in view: PDFView) {
            guard observedURL != url else { return }
            observedURL = url
            guard let document = PDFDocument(url: url) else { return }
            view.document = document
            slideCount.wrappedValue = document.pageCount
            if let firstPage = document.page(at: 0) { view.go(to: firstPage) }

            if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) }
            pageObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak self, weak view] _ in
                guard let self, let view, let document = view.document, let page = view.currentPage else { return }
                self.slideIndex.wrappedValue = document.index(for: page)
            }
        }
    }
}

private enum PresentationPreviewRenderer {
    static func renderPDF(for presentationURL: URL) -> URL? {
        let fileManager = FileManager.default
        let outputDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AuraAI", isDirectory: true)
            .appendingPathComponent("presentation-previews", isDirectory: true)
        guard let soffice = sofficeURL() else { return nil }

        do {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let outputURL = outputDirectory
                .appendingPathComponent(presentationURL.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("pdf")
            if fileManager.fileExists(atPath: outputURL.path) { return outputURL }

            let process = Process()
            process.executableURL = soffice
            process.arguments = ["--headless", "--convert-to", "pdf", "--outdir", outputDirectory.path, presentationURL.path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 && fileManager.fileExists(atPath: outputURL.path) ? outputURL : nil
        } catch {
            return nil
        }
    }

    private static func sofficeURL() -> URL? {
        let paths = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/opt/homebrew/bin/soffice",
            "/usr/local/bin/soffice"
        ]
        return paths.lazy.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private struct ImageFilePreview: View {
    let url: URL

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.12)
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: max(1, geometry.size.width - 32),
                            height: max(1, geometry.size.height - 32)
                        )
                        .padding(16)
                } else {
                    ContentUnavailableView(auraText("Image unavailable", "이미지를 열 수 없습니다"), systemImage: "photo")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
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
                        GFMMarkdownMessageView(content: message.displayContent)
                            .padding(.top, 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(message.displayContent)
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
        let lines = MarkdownSanitizer.renderable(content).components(separatedBy: .newlines)
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
        let sanitized = MarkdownSanitizer.renderable(source)
        if let attributed = try? AttributedString(markdown: sanitized, options: options) {
            return Text(attributed)
        }
        return Text(sanitized)
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
                .buttonStyle(ClickCursorPlainButtonStyle())
                .focusable(false)
                .focusEffectDisabled()
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
                .buttonStyle(ClickCursorBorderedButtonStyle())
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
                .buttonStyle(ClickCursorPlainButtonStyle())
                .focusable(false)
                .focusEffectDisabled()
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
            MemoryVaultSheet(title: auraText("What \(member.name) remembers", "\(koreanSubject(member.name)) 기억하는 내용"), vault: store.memberMemoryVault(member))
        }
        .onDisappear { store.saveSettings() }
    }

    private var connectionTab: some View {
        Form {
            Picker(auraText("Provider", "제공자"), selection: $store.settings.provider.kind) {
                ForEach(ProviderKind.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: store.settings.provider.kind) { _, kind in store.applyProviderPreset(kind) }
            ProviderConnectionFields()
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
                        .buttonStyle(ClickCursorPlainButtonStyle())
                        .help(auraText("Edit friend", "친구 편집"))
                    VStack(alignment: .leading) {
                        Text(member.name)
                        Text(member.role.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(auraText("Edit", "편집")) { editingMember = member }
                        .buttonStyle(ClickCursorBorderedButtonStyle())
                    Button(auraText("Memory", "기억")) { memoryMember = member }
                        .buttonStyle(ClickCursorBorderedButtonStyle())
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
                    .buttonStyle(ClickCursorPlainButtonStyle())
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
                            .buttonStyle(ClickCursorBorderedButtonStyle())
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
                                .buttonStyle(ClickCursorPlainButtonStyle())
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
                .buttonStyle(ClickCursorProminentButtonStyle())
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
                            .buttonStyle(ClickCursorPlainButtonStyle())
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
                    .buttonStyle(ClickCursorProminentButtonStyle())
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
                Button(auraText("Send redacted", "가림 처리본 보내기")) { store.approvePrivacy() }.buttonStyle(ClickCursorProminentButtonStyle())
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
                Button(auraText("Allow once", "한 번 허용")) { store.resolveApproval(true) }.buttonStyle(ClickCursorProminentButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 580, height: 360)
        .interactiveDismissDisabled()
    }
}
