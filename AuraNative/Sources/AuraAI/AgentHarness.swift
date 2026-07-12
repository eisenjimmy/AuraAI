import AppKit
import ApplicationServices
import Foundation

/// Aura's basic, permissioned agent loop. The model can propose one structured
/// operation at a time; the harness validates, approves, executes, observes,
/// and bounds every iteration.
struct AgentHarness {
    private let client = OpenAICompatibleClient()
    private let sandboxWorker = SandboxWorker()
    private let maximumSteps = 8

    func run(
        userPrompt: String,
        member: TeamMember,
        history: [ConversationMessage],
        configuration: ProviderConfiguration,
        globalMemory: String,
        memberMemory: String,
        workspace: URL?,
        authorizedFolders: [URL],
        skills: AgentSkillSettings,
        requestedArtifact: ArtifactIntent?,
        attachments: [ChatAttachment],
        memoryUpdate: MemoryUpdate? = nil,
        requestFolder: @escaping @MainActor (String) async -> URL?,
        approval: @escaping @MainActor (AgentApproval) async -> Bool,
        onEvent: @escaping @MainActor (AgentHarnessEvent) -> Void = { _ in },
        onTextDelta: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> AgentRunResult {
        var generatedAttachments: [ChatAttachment] = []
        var events: [AgentHarnessEvent] = []
        var loopGuard = AgentLoopGuard()
        var performedToolWork = false
        var readableFolders = authorizedFolders.map(\.standardizedFileURL)
        let requestedFolder = AgentFolderIntent.explicitFolder(in: userPrompt)
        let artifactSource = history.map(\.modelContent).joined(separator: "\n\n") + "\n\n" + userPrompt
        let artifactTitle = requestedArtifact.map { DocumentNaming.suggestedTitle(for: $0, source: artifactSource) }
        var initialFolderResult: String?

        let received = AgentHarnessEvent(
            kind: .received,
            step: 0,
            title: auraText("Task received", "작업을 받았습니다"),
            detail: auraText("Understanding the request and preparing a safe plan.", "요청을 이해하고 안전한 작업 순서를 준비합니다.")
        )
        events.append(received)
        await onEvent(received)

        // A clear request for a well-known user folder is an explicit user
        // intent. Ask the user to select it before a fallible model can fall
        // back to listing the unrelated workspace.
        if let requestedFolder,
           !readableFolders.contains(where: { $0.lastPathComponent.caseInsensitiveCompare(requestedFolder) == .orderedSame }) {
            guard let grantedFolder = await requestFolder(requestedFolder) else {
                let denied = AgentHarnessEvent(
                    kind: .denied,
                    step: 0,
                    title: auraText("Folder access was not granted", "폴더 접근이 허용되지 않았습니다"),
                    detail: requestedFolder
                )
                events.append(denied)
                await onEvent(denied)
                return AgentRunResult(response: "I couldn't inspect \(requestedFolder) because folder access was not granted.", attachments: [], events: events)
            }
            readableFolders.append(grantedFolder.standardizedFileURL)
        }

        if let requestedFolder,
           let folder = readableFolders.first(where: { $0.lastPathComponent.caseInsensitiveCompare(requestedFolder) == .orderedSame }) {
            initialFolderResult = try? AgentToolExecutor.listDirectory(folder)
        }

        var transcript = baseMessages(
            userPrompt: userPrompt,
            member: member,
            history: history,
            globalMemory: globalMemory,
            memberMemory: memberMemory,
            workspace: workspace,
            authorizedFolders: readableFolders,
            skills: skills,
            requiredFolder: requestedFolder,
            attachments: attachments,
            memoryUpdate: memoryUpdate
        )
        if let initialFolderResult {
            transcript.append(internalToolResult(initialFolderResult))
            performedToolWork = true
        }

        for step in 1...maximumSteps {
            let inferring = AgentHarnessEvent(
                kind: .inferring,
                step: step,
                title: auraText("Thinking through the next step", "다음 단계를 판단하는 중"),
                detail: auraText("Using the available workspace context and approved tools.", "작업 공간 맥락과 허용된 도구를 사용합니다.")
            )
            events.append(inferring)
            await onEvent(inferring)
            let streamGate = await MainActor.run { StreamVisibilityGate(onTextDelta: onTextDelta) }
            await streamGate.reset()
            let reply = try await client.stream(messages: transcript, configuration: configuration) { @MainActor delta in
                streamGate.receive(delta)
            }
            await streamGate.finish()
            guard let call = ToolCall.parse(reply) else {
                if let requestedArtifact, !skills.isEnabled(requestedArtifact.skill) {
                    return AgentRunResult(
                        response: auraText(
                            "The \(requestedArtifact.skill.title) skill is turned off in Settings, so I did not create a file.",
                            "설정에서 \(requestedArtifact.skill.title) 기능이 꺼져 있어 파일을 만들지 않았습니다."
                        ),
                        attachments: [],
                        events: events
                    )
                }
                if let requestedArtifact {
                    let fallback = AgentHarnessEvent(
                        kind: .toolRequested,
                        step: step,
                        title: requestedArtifact.fallbackTitle,
                        detail: requestedArtifact.fallbackDetail
                    )
                    events.append(fallback)
                    await onEvent(fallback)
                    do {
                        if let execution = try await fallbackExecution(
                            for: requestedArtifact,
                            prompt: artifactSource,
                            workspace: workspace,
                            approval: approval
                        ) {
                            if let failure = ArtifactValidator.validate(execution.attachments, expected: requestedArtifact, source: artifactSource) {
                                let invalid = AgentHarnessEvent(
                                    kind: .failed,
                                    step: step,
                                    title: auraText("Generated file did not validate", "생성된 파일 검증에 실패했습니다"),
                                    detail: failure
                                )
                                events.append(invalid)
                                await onEvent(invalid)
                                return AgentRunResult(response: failure, attachments: [], events: events)
                            }
                            if let attachment = execution.attachments.last {
                                let checking = AgentHarnessEvent(
                                    kind: .toolRequested,
                                    step: step,
                                    title: auraText("Checking the finished file", "완성된 파일을 다시 확인하는 중"),
                                    detail: auraText("An independent worker is checking the verified file evidence.", "독립 작업자가 검증된 파일 정보를 확인하고 있습니다.")
                                )
                                events.append(checking)
                                await onEvent(checking)
                                let verdict = await sandboxWorker.inspect(
                                    .artifactValidation(task: userPrompt, artifact: attachment, expected: requestedArtifact),
                                    configuration: configuration
                                )
                                if case .revise(let reason) = verdict {
                                    let rejected = AgentHarnessEvent(
                                        kind: .failed,
                                        step: step,
                                        title: auraText("File needs revision", "파일을 다시 다듬어야 합니다"),
                                        detail: auraText("The independent check found a material mismatch.", "독립 검토에서 중요한 불일치가 발견되었습니다.")
                                    )
                                    events.append(rejected)
                                    await onEvent(rejected)
                                    return AgentRunResult(response: reason, attachments: [], events: events)
                                }
                            }
                            let observation = AgentHarnessEvent.observation(for: execution, step: step)
                            events.append(observation)
                            await onEvent(observation)
                            return AgentRunResult(response: execution.output, attachments: execution.attachments, events: events)
                        }
                    } catch {
                        return AgentRunResult(response: error.localizedDescription, attachments: [], events: events)
                    }
                }
                if ToolProtocolSanitizer.containsInternalProtocol(in: reply) {
                    return AgentRunResult(
                        response: ToolProtocolSanitizer.userVisibleText(from: reply),
                        attachments: generatedAttachments,
                        events: events
                    )
                }
                if performedToolWork || requestedArtifact != nil {
                    let checking = AgentHarnessEvent(
                        kind: .toolRequested,
                        step: step,
                        title: auraText("Checking the completed work", "완료된 작업을 다시 확인하는 중"),
                        detail: auraText("An independent worker is checking the final answer against verified results.", "독립 작업자가 검증된 결과와 최종 답변을 대조하고 있습니다.")
                    )
                    events.append(checking)
                    await onEvent(checking)
                    let verdict = await sandboxWorker.inspect(
                        .responseValidation(task: userPrompt, response: reply, artifacts: generatedAttachments, toolWork: performedToolWork),
                        configuration: configuration
                    )
                    switch verdict {
                    case .approved:
                        let verified = AgentHarnessEvent(
                            kind: .observation,
                            step: step,
                            title: auraText("Independent check complete", "독립 검토가 완료되었습니다"),
                            detail: auraText("The final answer matches the verified work.", "최종 답변이 검증된 작업 결과와 일치합니다.")
                        )
                        events.append(verified)
                        await onEvent(verified)
                    case .revise(let reason):
                        let rejected = AgentHarnessEvent(
                            kind: .failed,
                            step: step,
                            title: auraText("Final answer needs revision", "최종 답변을 다듬어야 합니다"),
                            detail: auraText("The independent check found an unsupported or incomplete claim.", "독립 검토에서 근거가 부족하거나 빠진 내용이 발견되었습니다.")
                        )
                        events.append(rejected)
                        await onEvent(rejected)
                        await onTextDelta("")
                        transcript.append(internalToolResult("Isolated response validation requested revision: \(reason). Rewrite the final answer using only verified results. Do not call another tool unless work is actually incomplete."))
                        continue
                    case .unavailable:
                        break
                    }
                }
                let completed = AgentHarnessEvent(
                    kind: .completed,
                    step: step,
                    title: auraText("Task complete", "작업 완료"),
                    detail: auraText("The friend has finished the response.", "친구가 응답을 마쳤습니다.")
                )
                events.append(completed)
                await onEvent(completed)
                return AgentRunResult(response: reply, attachments: generatedAttachments, events: events)
            }
            guard loopGuard.allows(call) else {
                let stopped = AgentHarnessEvent(
                    kind: .failed,
                    step: step,
                    title: auraText("Stopped a repeated tool request", "반복된 도구 요청을 중단했습니다"),
                    detail: auraText("\(call.name) was requested too many times without new progress.", "\(call.name) 요청이 새로운 진전 없이 너무 많이 반복되었습니다.")
                )
                events.append(stopped)
                await onEvent(stopped)
                return AgentRunResult(
                    response: auraText(
                        "I stopped because the same tool request repeated without producing new progress. Please refine the request or review the last tool result.",
                        "같은 도구 요청이 새로운 진전 없이 반복되어 중단했습니다. 요청을 조금 더 구체화하거나 마지막 도구 결과를 확인해 주세요."
                    ),
                    attachments: generatedAttachments,
                    events: events
                )
            }
            if let requestedArtifact, requestedArtifact.conflicts(with: call.name) {
                let rejected = AgentHarnessEvent(
                    kind: .failed,
                    step: step,
                    title: auraText("Blocked the wrong document type", "잘못된 문서 형식을 차단했습니다"),
                    detail: auraText(
                        "The request is for \(requestedArtifact.skill.title), not \(call.name).",
                        "요청한 형식은 \(requestedArtifact.skill.title)이며 \(call.name)이 아닙니다."
                    )
                )
                events.append(rejected)
                await onEvent(rejected)
                transcript.append(internalToolRequest(call))
                transcript.append(internalToolResult(
                    "Refused: the user explicitly requested \(requestedArtifact.skill.title). Use \(requestedArtifact.skill.toolName), not \(call.name)."
                ))
                continue
            }
            let normalizedCall = requestedArtifact.map { $0.normalizing(call, title: artifactTitle ?? $0.defaultTitle) } ?? call
            if normalizedCall.name == "write_file",
               let path = normalizedCall.arguments["path"]?.stringValue,
               let content = normalizedCall.arguments["content"]?.stringValue,
               SandboxWorker.shouldReviewCode(path: path) {
                let checking = AgentHarnessEvent(
                    kind: .toolRequested,
                    step: step,
                    title: auraText("Reviewing the code draft", "코드 초안을 검토하는 중"),
                    detail: auraText("An isolated worker is checking the proposed source change before it is written.", "분리된 작업자가 파일을 쓰기 전에 소스 변경안을 확인하고 있습니다.")
                )
                events.append(checking)
                await onEvent(checking)
                let verdict = await sandboxWorker.inspect(.codeReview(task: userPrompt, path: path, content: content), configuration: configuration)
                if case .revise(let reason) = verdict {
                    let rejected = AgentHarnessEvent(
                        kind: .failed,
                        step: step,
                        title: auraText("Code draft needs revision", "코드 초안을 다듬어야 합니다"),
                        detail: auraText("The file was not written until the issue is corrected.", "문제가 수정될 때까지 파일을 쓰지 않았습니다.")
                    )
                    events.append(rejected)
                    await onEvent(rejected)
                    transcript.append(internalToolRequest(normalizedCall))
                    transcript.append(internalToolResult("Isolated code review rejected the draft before writing: \(reason). Produce a corrected file proposal."))
                    continue
                }
            }
            let progress = normalizedCall.progressPresentation
            let requested = AgentHarnessEvent(
                kind: .toolRequested,
                step: step,
                title: progress.title,
                detail: progress.detail
            )
            events.append(requested)
            await onEvent(requested)
            let execution = try await AgentToolExecutor.execute(
                normalizedCall,
                workspace: workspace,
                authorizedFolders: readableFolders,
                skills: skills,
                requestFolder: requestFolder,
                approval: approval
            )
            if let grantedFolder = execution.grantedFolder, !readableFolders.contains(grantedFolder) {
                readableFolders.append(grantedFolder)
            }
            performedToolWork = true
            if let requestedArtifact, !execution.attachments.isEmpty,
               let failure = ArtifactValidator.validate(execution.attachments, expected: requestedArtifact, source: artifactSource) {
                let invalid = AgentHarnessEvent(
                    kind: .failed,
                    step: step,
                    title: auraText("Generated file did not validate", "생성된 파일 검증에 실패했습니다"),
                    detail: failure
                )
                events.append(invalid)
                await onEvent(invalid)
                transcript.append(internalToolRequest(normalizedCall))
                transcript.append(internalToolResult("Validation failed: \(failure) Repair the requested artifact or explain the blocker."))
                continue
            }
            if let attachment = execution.attachments.last {
                let checking = AgentHarnessEvent(
                    kind: .toolRequested,
                    step: step,
                    title: auraText("Checking the finished file", "완성된 파일을 다시 확인하는 중"),
                    detail: auraText("An independent worker is checking the verified file evidence.", "독립 작업자가 검증된 파일 정보를 확인하고 있습니다.")
                )
                events.append(checking)
                await onEvent(checking)
                let verdict = await sandboxWorker.inspect(
                    .artifactValidation(task: userPrompt, artifact: attachment, expected: requestedArtifact),
                    configuration: configuration
                )
                if case .revise(let reason) = verdict {
                    let rejected = AgentHarnessEvent(
                        kind: .failed,
                        step: step,
                        title: auraText("File needs revision", "파일을 다시 다듬어야 합니다"),
                        detail: auraText("The independent check found a material mismatch.", "독립 검토에서 중요한 불일치가 발견되었습니다.")
                    )
                    events.append(rejected)
                    await onEvent(rejected)
                    transcript.append(internalToolRequest(normalizedCall))
                    transcript.append(internalToolResult("Isolated artifact validation requested revision: \(reason). Repair the artifact before reporting it as ready."))
                    continue
                }
            }
            generatedAttachments += execution.attachments
            let observation = AgentHarnessEvent.observation(for: execution, step: step)
            events.append(observation)
            await onEvent(observation)
            transcript.append(internalToolRequest(normalizedCall))
            transcript.append(internalToolResult(execution.output))
        }
        let limitReached = AgentHarnessEvent(
            kind: .failed,
            step: maximumSteps,
            title: auraText("Tool-step limit reached", "도구 단계 한도에 도달했습니다"),
            detail: auraText("Aura stopped after \(maximumSteps) bounded tool steps.", "Aura는 \(maximumSteps)회의 제한된 도구 단계를 마치고 중단했습니다.")
        )
        events.append(limitReached)
        await onEvent(limitReached)
        return AgentRunResult(
            response: "I stopped after \(maximumSteps) tool steps. The work may be incomplete; review the activity and continue with a more specific instruction.",
            attachments: generatedAttachments,
            events: events
        )
    }

    private func baseMessages(
        userPrompt: String,
        member: TeamMember,
        history: [ConversationMessage],
        globalMemory: String,
        memberMemory: String,
        workspace: URL?,
        authorizedFolders: [URL],
        skills: AgentSkillSettings,
        requiredFolder: String?,
        attachments: [ChatAttachment],
        memoryUpdate: MemoryUpdate?
    ) -> [ModelMessage] {
        let workspaceDescription = workspace?.path ?? "No workspace selected. Do not request file or shell tools."
        let folderDescription = authorizedFolders.isEmpty
            ? "No extra folders have been approved."
            : authorizedFolders.map(\.path).joined(separator: ", ")
        let targetInstruction = requiredFolder.map {
            "The current request explicitly targets the approved \($0) folder. Report only what the internal folder result confirms."
        } ?? ""
        let enabledDocumentTools = AgentSkill.allCases.filter(skills.isEnabled).map(\.toolName)
        let toolNames = (["list_files", "read_file", "request_folder_access", "write_file"] + enabledDocumentTools + ["run_shell", "computer"]).joined(separator: "|")
        let documentToolInstructions = enabledDocumentTools.isEmpty
            ? "Document creation skills are disabled. Do not call a document creation tool."
            : [
                skills.isEnabled(.markdown) ? "create_markdown_document {\"path\":\"report.md\",\"content\":\"# Report\\n...\"}." : nil,
                skills.isEnabled(.html) ? "create_html_document {\"path\":\"report.html\",\"title\":\"Report\",\"summary\":\"One-line summary\",\"body_html\":\"<section><h2>Findings</h2><p>...</p></section>\"}." : nil,
                skills.isEnabled(.spreadsheet) ? "create_spreadsheet {\"path\":\"report.xlsx\",\"sheet\":\"Summary\",\"title\":\"Report\",\"headers\":[\"Item\",\"Amount\"],\"rows\":[[\"Example\",1250],[\"Active\",true]]}." : nil,
                skills.isEnabled(.word) ? "create_word_document {\"path\":\"brief.docx\",\"title\":\"Project Brief\",\"content\":\"## Decision\\nParagraph text\\n- First action\"}." : nil,
                skills.isEnabled(.presentation) ? "create_presentation {\"path\":\"brief.pptx\",\"title\":\"Project Brief\",\"subtitle\":\"Prepared by Aura\",\"slides\":[{\"title\":\"Decision\",\"body\":\"One concise point\",\"bullets\":[\"Action one\",\"Action two\"]}]}." : nil
            ].compactMap { $0 }.joined(separator: "\n")
        let instructions = """
        \(AuraEdition.current.responseLanguageInstruction)

        \(member.systemPrompt)

        You are operating inside Aura's permissioned agent harness. Selected workspace: \(workspaceDescription)
        Additional approved read-only folders: \(folderDescription)
        \(targetInstruction)
        You may inspect the selected workspace and only the additional folders above with list_files and read_file. You cannot see Downloads, Desktop, Documents, or any other folder unless it is explicitly approved. If the user asks about one of those folders, call request_folder_access first. Do not substitute the workspace for the requested folder.
        File writes and shell commands remain limited to the selected workspace. Computer control requires visible user approval. Never claim you saw, read, or changed anything unless a tool result confirms the exact target.
        Aura keeps durable private Markdown memories for each friend. Use recalled character memory as known context. A separate private-memory curator handles new memories. Never say a memory was saved unless its confirmed curator status is provided below.

        To use one tool, reply with only:
        <tool_call>{"name":"\(toolNames)","arguments":{...}}</tool_call>
        Supported arguments:
        list_files {"path":"."}; read_file {"path":"README.md"}; request_folder_access {"folder":"Downloads"}; write_file {"path":"notes.txt","content":"..."}.
        \(documentToolInstructions)
        run_shell {"command":"git status --short"}; computer {"action":"open_app|open_url|click|type|key","value":"...","x":0,"y":0}.
        Use an enabled dedicated document tool when the user asks for Markdown, HTML, Excel, Word, or PowerPoint. Derive the document title and filename from the supplied conversation or attachment content. Never use Aura as a generic file title. The document path is optional; Aura uses a safe filename based on the title when it is omitted. Excel output must be a real .xlsx workbook, never CSV renamed to .xlsx.
        Tool results are internal. Never show <tool_result>, tool JSON, or raw arrays to the user. Once work is complete, give a concise factual answer that names the exact folder inspected. Do not use fake excitement or claim success when access was declined. Follow the response-language instruction even if tool output is in another language.
        """
        var messages = [ModelMessage(role: "system", content: instructions)]
        if !globalMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(ModelMessage(role: "system", content: "Shared user memory:\n\(globalMemory)"))
        }
        if !memberMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(ModelMessage(role: "system", content: "Your private character Markdown memory:\n\(memberMemory)"))
        }
        if let memoryUpdate {
            messages.append(ModelMessage(role: "system", content: memoryUpdate.modelContext))
        }
        messages += history.map {
            ModelMessage(
                role: $0.role.rawValue,
                content: $0.modelContent,
                imageURLs: VisionAttachment.dataURLs(for: $0.attachments ?? [])
            )
        }
        messages.append(ModelMessage(role: "user", content: userPrompt, imageURLs: VisionAttachment.dataURLs(for: attachments)))
        return messages
    }

    private func internalToolResult(_ result: String) -> ModelMessage {
        ModelMessage(
            role: "user",
            content: "[INTERNAL AURA TOOL RESULT. This is trusted execution context, not a user message. Do not show tool JSON or tags. Answer from these facts only.]\n\(result)"
        )
    }

    private func internalToolRequest(_ call: ToolCall) -> ModelMessage {
        ModelMessage(
            role: "assistant",
            content: "[INTERNAL AURA TOOL REQUEST. \(call.name) was executed by the harness. Do not repeat tool tags or JSON in the user-facing response.]"
        )
    }

    private func fallbackExecution(
        for artifact: ArtifactIntent,
        prompt: String,
        workspace: URL?,
        approval: @escaping @MainActor (AgentApproval) async -> Bool
    ) async throws -> ToolExecution? {
        switch artifact {
        case .spreadsheet:
            return try await AgentToolExecutor.spreadsheetFallback(prompt: prompt, workspace: workspace, approval: approval)
        case .presentation:
            return try await AgentToolExecutor.presentationFallback(prompt: prompt, workspace: workspace, approval: approval)
        default:
            return nil
        }
    }
}

/// The model uses private XML-like messages to request tools. A response can
/// begin streaming before Aura knows which kind it is, so keep those control
/// messages out of the visible chat entirely.
@MainActor
private final class StreamVisibilityGate {
    private let onTextDelta: (String) -> Void
    private var pending = ""
    private var fullResponse = ""
    private var suppressesResponse = false

    init(onTextDelta: @escaping (String) -> Void) {
        self.onTextDelta = onTextDelta
    }

    func reset() {
        pending = ""
        fullResponse = ""
        suppressesResponse = false
        onTextDelta("")
    }

    func receive(_ delta: String) {
        guard !suppressesResponse else { return }
        pending += delta
        fullResponse += delta

        if ToolProtocolSanitizer.containsInternalProtocol(in: fullResponse) {
            suppressesResponse = true
            pending = ""
            onTextDelta("")
            return
        }

        if ToolProtocolSanitizer.isPotentialInternalProtocolPrefix(pending) {
            return
        }

        onTextDelta(pending)
        pending = ""
    }

    func finish() {
        guard !suppressesResponse, !pending.isEmpty else { return }
        onTextDelta(pending)
        pending = ""
    }
}

struct AgentRunResult {
    var response: String
    var attachments: [ChatAttachment]
    var events: [AgentHarnessEvent] = []
}

enum AgentHarnessEventKind: String, Codable, Equatable, Sendable {
    case received
    case inferring
    case toolRequested
    case observation
    case denied
    case completed
    case failed
}

/// A concise, user-visible trace. Full model reasoning and raw tool output
/// remain private; the event only records the operation and its outcome.
struct AgentHarnessEvent: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var kind: AgentHarnessEventKind
    var step: Int
    var title: String
    var detail: String
    var createdAt = Date()

    static func observation(for execution: ToolExecution, step: Int) -> AgentHarnessEvent {
        let output = execution.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDenied = output.localizedCaseInsensitiveContains("declined") || output.localizedCaseInsensitiveContains("cancelled")
        let isFailure = output.hasPrefix("Refused:") || output.hasPrefix("Unknown tool") || output.hasPrefix("The ") && output.localizedCaseInsensitiveContains("skill is disabled")
        let fileName = execution.attachments.last?.fileName
        let presentation: (title: String, detail: String)
        if let fileName {
            presentation = (
                auraText("Your file is ready", "파일이 준비되었습니다"),
                auraText("Created \(fileName).", "\(fileName)을(를) 만들었습니다.")
            )
        } else if isDenied {
            presentation = (
                auraText("Waiting for your approval", "승인을 기다리고 있습니다"),
                auraText("That step was not completed without your permission.", "허용해 주시기 전에는 이 단계를 진행하지 않았습니다.")
            )
        } else if isFailure {
            presentation = (
                auraText("That step needs attention", "이 단계는 확인이 필요합니다"),
                auraText("I could not safely complete it yet.", "아직 안전하게 완료할 수 없었습니다.")
            )
        } else {
            presentation = (
                auraText("Step complete", "단계 완료"),
                auraText("I have the information needed for the next step.", "다음 단계를 위한 정보를 확인했습니다.")
            )
        }
        return AgentHarnessEvent(
            kind: isDenied ? .denied : (isFailure ? .failed : .observation),
            step: step,
            title: presentation.title,
            detail: presentation.detail
        )
    }
}

/// Prevents small local models from spinning on a request whose prior result
/// is already in the transcript. Two attempts are allowed for benign repairs.
struct AgentLoopGuard {
    private var requestCounts: [String: Int] = [:]

    mutating func allows(_ call: ToolCall) -> Bool {
        let signature = call.signature
        requestCounts[signature, default: 0] += 1
        return requestCounts[signature, default: 0] <= 2
    }
}

enum AgentFolderIntent {
    static func explicitFolder(in text: String) -> String? {
        let lowercased = text.lowercased()
        if lowercased.contains("download") || text.contains("다운로드") { return "Downloads" }
        if lowercased.contains("desktop") || text.contains("바탕화면") { return "Desktop" }
        if lowercased.contains("documents") || text.contains("문서") { return "Documents" }
        return nil
    }
}

enum ArtifactIntent: Equatable {
    case spreadsheet
    case presentation
    case word
    case markdown
    case html

    var skill: AgentSkill {
        switch self {
        case .spreadsheet: return .spreadsheet
        case .presentation: return .presentation
        case .word: return .word
        case .markdown: return .markdown
        case .html: return .html
        }
    }

    var fileExtension: String {
        switch self {
        case .spreadsheet: return "xlsx"
        case .presentation: return "pptx"
        case .word: return "docx"
        case .markdown: return "md"
        case .html: return "html"
        }
    }

    var defaultTitle: String {
        switch self {
        case .spreadsheet: return auraText("Summary", "요약")
        case .presentation: return auraText("Presentation", "프레젠테이션")
        case .word: return auraText("Document", "문서")
        case .markdown: return auraText("Notes", "메모")
        case .html: return auraText("Report", "보고서")
        }
    }

    var fallbackTitle: String {
        switch self {
        case .spreadsheet: return auraText("Creating the spreadsheet", "엑셀 파일을 만드는 중")
        case .presentation: return auraText("Creating the PowerPoint", "PowerPoint를 만드는 중")
        default: return auraText("Preparing the document", "문서를 준비하는 중")
        }
    }

    var fallbackDetail: String {
        switch self {
        case .spreadsheet: return auraText("Using Aura's safe spreadsheet fallback.", "Aura의 안전한 엑셀 생성 경로를 사용합니다.")
        case .presentation: return auraText("Using Aura's safe PowerPoint fallback.", "Aura의 안전한 PowerPoint 생성 경로를 사용합니다.")
        default: return auraText("Waiting for the friend to choose the document tool.", "친구가 문서 도구를 선택하는 중입니다.")
        }
    }

    func conflicts(with toolName: String) -> Bool {
        toolName.hasPrefix("create_") && toolName != skill.toolName
    }

    func normalizing(_ call: ToolCall, title: String) -> ToolCall {
        guard call.name == skill.toolName else { return call }
        var arguments = call.arguments
        let requestedTitle = arguments["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if requestedTitle.isEmpty || requestedTitle.localizedCaseInsensitiveContains("aura") {
            arguments["title"] = .string(title)
        }
        let requestedPath = arguments["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if requestedPath.isEmpty || requestedPath.localizedCaseInsensitiveContains("aura") {
            arguments["path"] = .string(DocumentNaming.filename(title: title, fileExtension: fileExtension))
        }
        return ToolCall(name: call.name, arguments: arguments)
    }

    static func requested(in text: String) -> ArtifactIntent? {
        let lower = text.lowercased()
        // Output requests take precedence over source material. A request for a
        // deck built from an Excel/PDF file must still create a presentation.
        if lower.contains("powerpoint") || lower.contains("power point") || lower.contains("slide deck") || lower.contains("slides") || lower.contains("presentation") || lower.contains(".pptx") || text.contains("파워포인트") || text.contains("프레젠테이션") || text.contains("슬라이드") {
            return .presentation
        }
        if lower.contains("word document") || lower.contains(".docx") || text.contains("워드 문서") {
            return .word
        }
        if lower.contains("excel") || lower.contains("spreadsheet") || lower.contains(".xlsx") || text.contains("엑셀") {
            return .spreadsheet
        }
        if lower.contains("markdown") || lower.contains(".md") || text.contains("마크다운") {
            return .markdown
        }
        if lower.contains("html") || lower.contains("web page") || text.contains("웹페이지") {
            return .html
        }
        return nil
    }
}

enum SpreadsheetIntent {
    static func isRequested(_ text: String) -> Bool {
        ArtifactIntent.requested(in: text) == .spreadsheet
    }
}

struct ToolCall: Decodable {
    var name: String
    var arguments: [String: JSONValue]

    var signature: String {
        let serializedArguments = arguments.keys.sorted().map { key in
            "\(key)=\(arguments[key]?.stableText ?? "null")"
        }.joined(separator: "&")
        return "\(name):\(serializedArguments)"
    }

    var safeSummary: String {
        let keys = arguments.keys.sorted()
        guard !keys.isEmpty else { return auraText("No arguments", "인수 없음") }
        return auraText("Arguments: \(keys.joined(separator: ", "))", "인수: \(keys.joined(separator: ", "))")
    }

    var progressPresentation: (title: String, detail: String) {
        switch name {
        case "list_files":
            return (auraText("Checking the selected folder", "선택한 폴더를 확인하는 중"), auraText("Looking for the files relevant to your request.", "요청과 관련된 파일을 찾고 있습니다."))
        case "read_file":
            return (auraText("Reading the file", "파일을 읽는 중"), auraText("Reviewing the information you asked about.", "요청하신 정보를 살펴보고 있습니다."))
        case "request_folder_access":
            return (auraText("Requesting folder access", "폴더 접근 권한을 요청하는 중"), auraText("I need your permission before looking there.", "해당 위치를 보기 전에 허용이 필요합니다."))
        case "write_file":
            return (auraText("Preparing your file", "파일을 준비하는 중"), auraText("Putting the requested information into a file.", "요청하신 내용을 파일로 정리하고 있습니다."))
        case "create_spreadsheet":
            return (auraText("Organizing the spreadsheet", "엑셀을 정리하는 중"), auraText("Turning the information into clear rows and columns.", "정보를 보기 쉬운 행과 열로 정리하고 있습니다."))
        case "create_presentation":
            return (auraText("Building the presentation", "프레젠테이션을 만드는 중"), auraText("Arranging the key points into slides.", "핵심 내용을 슬라이드로 구성하고 있습니다."))
        case "create_word_document", "create_markdown_document", "create_html_document":
            return (auraText("Drafting the document", "문서를 작성하는 중"), auraText("Organizing the requested material into a clear document.", "요청하신 내용을 읽기 쉬운 문서로 정리하고 있습니다."))
        case "run_shell":
            return (auraText("Checking the workspace", "작업 공간을 확인하는 중"), auraText("Verifying the requested work safely.", "요청하신 작업을 안전하게 확인하고 있습니다."))
        case "computer":
            return (auraText("Using your Mac", "Mac에서 작업하는 중"), auraText("Completing the action you approved.", "허용하신 작업을 진행하고 있습니다."))
        default:
            return (auraText("Working on the next step", "다음 단계를 진행하는 중"), auraText("Taking the next safe action for your request.", "요청을 위한 다음 안전한 작업을 진행하고 있습니다."))
        }
    }

    static func parse(_ text: String) -> ToolCall? {
        guard let start = text.range(of: "<tool_call>"),
              let json = firstJSONObject(in: text[start.upperBound...]) else { return nil }
        let data = Data(json.utf8)
        if let call = try? JSONDecoder().decode(ToolCall.self, from: data) { return call }

        // Smaller local models sometimes omit the documented `arguments`
        // envelope. Accept that flat form while preserving the same executor.
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object.removeValue(forKey: "name") as? String,
              let argumentsData = try? JSONSerialization.data(withJSONObject: object),
              let arguments = try? JSONDecoder().decode([String: JSONValue].self, from: argumentsData) else {
            return nil
        }
        return ToolCall(name: name, arguments: arguments)
    }

    /// Local models occasionally omit the closing tag or add a stray token
    /// after valid JSON. Recover the first balanced object without accepting
    /// arbitrary trailing model prose as tool input.
    private static func firstJSONObject(in text: Substring) -> String? {
        guard let objectStart = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = objectStart

        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[objectStart...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(Bool.self) { self = .boolean(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        self = .null
    }

    var stringValue: String? { if case .string(let value) = self { return value } else { return nil } }
    var intValue: Int? { if case .number(let value) = self { return Int(value) } else { return nil } }
    var arrayValue: [JSONValue]? { if case .array(let value) = self { return value } else { return nil } }
    var objectValue: [String: JSONValue]? { if case .object(let value) = self { return value } else { return nil } }

    var stableText: String {
        switch self {
        case .string(let value): return "string:\(value)"
        case .number(let value): return "number:\(value)"
        case .boolean(let value): return "boolean:\(value)"
        case .object(let value):
            let serializedObject = value.keys.sorted().map { key in
                "\(key):\(value[key]?.stableText ?? "null")"
            }.joined(separator: ",")
            return "object:{\(serializedObject)}"
        case .array(let value): return "array:[\(value.map(\.stableText).joined(separator: ","))]"
        case .null: return "null"
        }
    }
}

struct ToolExecution {
    var output: String
    var grantedFolder: URL?
    var attachments: [ChatAttachment] = []
}

private enum AgentToolExecutor {
    static func execute(
        _ call: ToolCall,
        workspace: URL?,
        authorizedFolders: [URL],
        skills: AgentSkillSettings,
        requestFolder: @escaping @MainActor (String) async -> URL?,
        approval: @escaping @MainActor (AgentApproval) async -> Bool
    ) async throws -> ToolExecution {
        switch call.name {
        case "list_files":
            let directory = try AgentPathResolver.resolveReadable(
                call.arguments["path"]?.stringValue ?? ".",
                workspace: workspace,
                authorizedFolders: authorizedFolders
            )
            return ToolExecution(output: try listDirectory(directory), grantedFolder: nil)
        case "read_file":
            let file = try AgentPathResolver.resolveReadable(
                required("path", call.arguments),
                workspace: workspace,
                authorizedFolders: authorizedFolders
            )
            let data = try Data(contentsOf: file)
            guard data.count <= 200_000 else { return ToolExecution(output: "Refused: file exceeds 200 KB read limit.", grantedFolder: nil) }
            return ToolExecution(output: String(data: data, encoding: .utf8) ?? "Refused: file is not UTF-8 text.", grantedFolder: nil)
        case "request_folder_access":
            let folder = try required("folder", call.arguments)
            guard let grantedFolder = await requestFolder(folder) else {
                return ToolExecution(output: "Folder access was declined or cancelled. Do not claim that the folder was inspected.", grantedFolder: nil)
            }
            return ToolExecution(
                output: "Folder access granted for \(grantedFolder.path). To inspect it, call list_files with path \"\(grantedFolder.lastPathComponent)\".",
                grantedFolder: grantedFolder
            )
        case "write_file":
            let path = try required("path", call.arguments)
            let content = try required("content", call.arguments)
            let file = try AgentPathResolver.resolveWorkspace(path, workspace: workspace)
            let preview = String(content.prefix(900))
            let allowed = await approval(AgentApproval(kind: .writeFile, title: "Write \(file.lastPathComponent)", detail: preview))
            guard allowed else { return ToolExecution(output: "User declined the file write.", grantedFolder: nil) }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
            return ToolExecution(output: "Wrote \(content.utf8.count) bytes to \(path).", grantedFolder: nil)
        case "create_markdown_document":
            guard skills.isEnabled(.markdown) else { return disabledSkill("Markdown") }
            let path = AgentArtifactPath.path(from: call.arguments, title: nil, fileExtension: "md")
            let content = try required("content", call.arguments)
            let file = try AgentPathResolver.resolveWorkspace(path, workspace: workspace)
            let allowed = await approval(AgentApproval(
                kind: .writeFile,
                title: "Create \(file.lastPathComponent)",
                detail: String(content.prefix(1_200))
            ))
            guard allowed else { return ToolExecution(output: "User declined the Markdown document write.", grantedFolder: nil) }
            try ArtifactWriter.markdown(content: content, to: file)
            return ToolExecution(output: "Created Markdown document at \(path).", grantedFolder: nil, attachments: [generatedAttachment(file, kind: "Markdown document")])
        case "create_html_document":
            guard skills.isEnabled(.html) else { return disabledSkill("HTML") }
            let title = AgentArtifactPath.title(from: call.arguments, fallback: ArtifactIntent.html.defaultTitle)
            let path = AgentArtifactPath.path(from: call.arguments, title: title, fileExtension: "html")
            let summary = call.arguments["summary"]?.stringValue ?? ""
            let body = try required("body_html", call.arguments)
            let file = try AgentPathResolver.resolveWorkspace(path, workspace: workspace)
            let allowed = await approval(AgentApproval(
                kind: .writeFile,
                title: "Create \(file.lastPathComponent)",
                detail: "\(title)\n\n\(String(body.prefix(1_000)))"
            ))
            guard allowed else { return ToolExecution(output: "User declined the HTML document write.", grantedFolder: nil) }
            try ArtifactWriter.html(title: title, summary: summary, bodyHTML: body, to: file)
            return ToolExecution(output: "Created self-contained HTML document at \(path).", grantedFolder: nil, attachments: [generatedAttachment(file, kind: "HTML document")])
        case "create_spreadsheet":
            guard skills.isEnabled(.spreadsheet) else { return disabledSkill("Excel") }
            let title = AgentArtifactPath.title(from: call.arguments, fallback: ArtifactIntent.spreadsheet.defaultTitle)
            let path = AgentArtifactPath.path(from: call.arguments, title: title, fileExtension: "xlsx")
            let sheet = call.arguments["sheet"]?.stringValue ?? "Summary"
            let headers = (optionalArray(["headers", "columns", "fields"], call.arguments) ?? [])
                .map(\.displayText)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let rows = (optionalArray(["rows", "data"], call.arguments) ?? []).compactMap(\.arrayValue)
            guard !headers.isEmpty else { throw LLMClientError.badResponse("Spreadsheet requires a headers or columns array.") }
            let file = try AgentPathResolver.resolveWorkspace(path, workspace: workspace)
            let allowed = await approval(AgentApproval(
                kind: .writeFile,
                title: "Create \(file.lastPathComponent)",
                detail: "\(title)\n\(headers.joined(separator: " | "))\n\(rows.count) data rows"
            ))
            guard allowed else { return ToolExecution(output: "User declined the Excel workbook write.", grantedFolder: nil) }
            try ArtifactWriter.spreadsheet(title: title, sheetName: sheet, headers: headers, rows: rows, to: file)
            return ToolExecution(output: "Created Excel workbook at \(path) with \(rows.count) data rows.", grantedFolder: nil, attachments: [generatedAttachment(file, kind: "Excel workbook")])
        case "create_word_document":
            guard skills.isEnabled(.word) else { return disabledSkill("Word") }
            let title = AgentArtifactPath.title(from: call.arguments, fallback: ArtifactIntent.word.defaultTitle)
            let path = AgentArtifactPath.path(from: call.arguments, title: title, fileExtension: "docx")
            let content = try required("content", call.arguments)
            let file = try AgentPathResolver.resolveWorkspace(path, workspace: workspace)
            let allowed = await approval(AgentApproval(
                kind: .writeFile,
                title: "Create \(file.lastPathComponent)",
                detail: "\(title)\n\n\(String(content.prefix(1_000)))"
            ))
            guard allowed else { return ToolExecution(output: "User declined the Word document write.", grantedFolder: nil) }
            try ArtifactWriter.word(title: title, content: content, to: file)
            return ToolExecution(output: "Created Word document at \(path).", grantedFolder: nil, attachments: [generatedAttachment(file, kind: "Word document")])
        case "create_presentation":
            guard skills.isEnabled(.presentation) else { return disabledSkill("PowerPoint") }
            let title = AgentArtifactPath.title(from: call.arguments, fallback: ArtifactIntent.presentation.defaultTitle)
            let path = AgentArtifactPath.path(from: call.arguments, title: title, fileExtension: "pptx")
            let subtitle = call.arguments["subtitle"]?.stringValue ?? ""
            let slides = try presentationSlides(from: requiredArray("slides", call.arguments))
            let file = try AgentPathResolver.resolveWorkspace(path, workspace: workspace)
            let preview = slides.prefix(8).map { $0.title }.joined(separator: "\n")
            let allowed = await approval(AgentApproval(
                kind: .writeFile,
                title: "Create \(file.lastPathComponent)",
                detail: "\(title)\n\n\(preview)"
            ))
            guard allowed else { return ToolExecution(output: "User declined the PowerPoint write.", grantedFolder: nil) }
            try ArtifactWriter.presentation(title: title, subtitle: subtitle, slides: slides, to: file)
            return ToolExecution(output: "Created PowerPoint presentation at \(path) with \(slides.count + 1) slides.", grantedFolder: nil, attachments: [generatedAttachment(file, kind: "PowerPoint presentation")])
        case "run_shell":
            let command = try required("command", call.arguments)
            let root = try AgentPathResolver.workspaceRoot(workspace)
            let allowed = await approval(AgentApproval(kind: .shell, title: "Run command", detail: "\(root.path)\n\n\(command)"))
            guard allowed else { return ToolExecution(output: "User declined the command.", grantedFolder: nil) }
            return ToolExecution(output: try runShell(command, in: root), grantedFolder: nil)
        case "computer":
            let action = try required("action", call.arguments)
            let value = call.arguments["value"]?.stringValue ?? ""
            let x = call.arguments["x"]?.intValue ?? 0
            let y = call.arguments["y"]?.intValue ?? 0
            let summary = action == "click" ? "Click at (\(x), \(y))" : "\(action): \(value)"
            let allowed = await approval(AgentApproval(kind: .computer, title: "Control your Mac", detail: summary))
            guard allowed else { return ToolExecution(output: "User declined computer control.", grantedFolder: nil) }
            return ToolExecution(output: try ComputerController.perform(action: action, value: value, x: x, y: y), grantedFolder: nil)
        default:
            return ToolExecution(output: "Unknown tool \(call.name). Use only documented Aura tools.", grantedFolder: nil)
        }
    }

    private static func required(_ key: String, _ values: [String: JSONValue]) throws -> String {
        guard let value = values[key]?.stringValue, !value.isEmpty else {
            throw LLMClientError.badResponse("Tool requires a non-empty \(key).")
        }
        return value
    }

    private static func generatedAttachment(_ file: URL, kind: String) -> ChatAttachment {
        ChatAttachment(
            fileName: file.lastPathComponent,
            storedPath: file.path,
            kind: kind,
            extractedText: ""
        )
    }

    private static func disabledSkill(_ name: String) -> ToolExecution {
        ToolExecution(output: "The \(name) document skill is disabled in Aura Settings. Do not claim the file was created.", grantedFolder: nil)
    }

    private static func requiredArray(_ key: String, _ values: [String: JSONValue]) throws -> [JSONValue] {
        guard let value = values[key]?.arrayValue else {
            throw LLMClientError.badResponse("Tool requires a \(key) array.")
        }
        return value
    }

    private static func optionalArray(_ keys: [String], _ values: [String: JSONValue]) -> [JSONValue]? {
        keys.lazy.compactMap { values[$0]?.arrayValue }.first
    }

    static func spreadsheetFallback(
        prompt: String,
        workspace: URL?,
        approval: @escaping @MainActor (AgentApproval) async -> Bool
    ) async throws -> ToolExecution {
        let lines = DocumentNaming.meaningfulLines(in: prompt, limit: 500)
        let isCharacterList = prompt.lowercased().contains("character") || prompt.contains("등장인물")
        let title = DocumentNaming.suggestedTitle(for: .spreadsheet, source: prompt)
        let path = AgentArtifactPath.path(from: [:], title: title, fileExtension: "xlsx")
        let file = try AgentPathResolver.resolveWorkspace(path, workspace: workspace)
        let headers = [auraText(isCharacterList ? "Character or source text" : "Source text", isCharacterList ? "등장인물 또는 원문" : "원문")]
        let rows = lines.map { [JSONValue.string($0)] }
        let allowed = await approval(AgentApproval(
            kind: .writeFile,
            title: "Create \(file.lastPathComponent)",
            detail: "\(title)\n\(rows.count) rows extracted from the request"
        ))
        guard allowed else { return ToolExecution(output: "User declined the Excel workbook write.", grantedFolder: nil) }
        try ArtifactWriter.spreadsheet(title: title, sheetName: "Summary", headers: headers, rows: rows, to: file)
        return ToolExecution(
            output: auraText("Created Excel workbook at \(file.path).", "Excel 워크북을 \(file.path)에 만들었습니다."),
            grantedFolder: nil,
            attachments: [generatedAttachment(file, kind: "Excel workbook")]
        )
    }

    static func presentationFallback(
        prompt: String,
        workspace: URL?,
        approval: @escaping @MainActor (AgentApproval) async -> Bool
    ) async throws -> ToolExecution {
        let sourceLines = DocumentNaming.meaningfulLines(in: prompt, limit: 60)
        let title = DocumentNaming.suggestedTitle(for: .presentation, source: prompt)
        let path = AgentArtifactPath.path(from: [:], title: title, fileExtension: "pptx")
        let file = try AgentPathResolver.resolveWorkspace(path, workspace: workspace)
        let groups = stride(from: 0, to: sourceLines.count, by: 4).map { start in
            Array(sourceLines.dropFirst(start).prefix(4))
        }
        let slides = groups.prefix(6).enumerated().map { index, group in
            PresentationSlide(
                title: group.first.map { String($0.prefix(90)) } ?? auraText("Overview", "개요"),
                body: index == 0 ? auraText("Source overview", "원문 개요") : "",
                bullets: Array(group.dropFirst()).map { String($0.prefix(180)) }
            )
        }
        let contentSlides = slides.isEmpty
            ? [PresentationSlide(title: auraText("Overview", "개요"), body: auraText("No readable source text was available.", "읽을 수 있는 원문이 없습니다."), bullets: [])]
            : slides
        let allowed = await approval(AgentApproval(
            kind: .writeFile,
            title: "Create \(file.lastPathComponent)",
            detail: "\(title)\n\(contentSlides.count + 1) slides"
        ))
        guard allowed else { return ToolExecution(output: "User declined the PowerPoint write.", grantedFolder: nil) }
        try ArtifactWriter.presentation(
            title: title,
            subtitle: auraText("Prepared from the conversation context", "대화 맥락을 바탕으로 정리") ,
            slides: contentSlides,
            to: file
        )
        return ToolExecution(
            output: auraText("Created PowerPoint presentation at \(file.path).", "PowerPoint 프레젠테이션을 \(file.path)에 만들었습니다."),
            grantedFolder: nil,
            attachments: [generatedAttachment(file, kind: "PowerPoint presentation")]
        )
    }

    private static func presentationSlides(from values: [JSONValue]) throws -> [PresentationSlide] {
        let slides = try values.map { value -> PresentationSlide in
            guard let object = value.objectValue,
                  let title = object["title"]?.stringValue,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LLMClientError.badResponse("Each presentation slide requires a title.")
            }
            return PresentationSlide(
                title: title,
                body: object["body"]?.stringValue ?? "",
                bullets: object["bullets"]?.arrayValue?.compactMap(\.stringValue) ?? []
            )
        }
        guard !slides.isEmpty, slides.count <= 30 else {
            throw LLMClientError.badResponse("Presentation requires 1 to 30 slides.")
        }
        return slides
    }

    static func listDirectory(_ directory: URL) throws -> String {
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .sorted()
            .prefix(300)
            .joined(separator: "\n")
        return "Listed \(directory.path). These are the actual entries in that folder:\n\(contents)"
    }

    private static func runShell(_ command: String, in workspace: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workspace
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = (stdout + (stderr.isEmpty ? "" : "\nSTDERR:\n\(stderr)"))
        return "Exit \(process.terminationStatus):\n\(combined.prefix(12_000))"
    }
}

/// Resolves file reads against explicit user-granted roots. Relative paths
/// remain workspace-relative unless their first component names an approved
/// folder such as "Downloads".
enum AgentPathResolver {
    static func workspaceRoot(_ workspace: URL?) throws -> URL {
        guard let workspace else { throw AuraStoreError.invalidWorkspace }
        return workspace.standardizedFileURL
    }

    static func resolveWorkspace(_ path: String, workspace: URL?) throws -> URL {
        let root = try workspaceRoot(workspace)
        let candidate = candidateURL(path, relativeTo: root)
        guard isContained(candidate, by: root) else {
            throw LLMClientError.badResponse("Refused: requested path escapes the selected workspace.")
        }
        return candidate
    }

    static func resolveReadable(_ path: String, workspace: URL?, authorizedFolders: [URL]) throws -> URL {
        let workspaceRoot = try workspaceRoot(workspace)
        let roots = [workspaceRoot] + authorizedFolders.map(\.standardizedFileURL)
        let request = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return workspaceRoot }

        let expanded = (request as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: expanded).standardizedFileURL
            guard roots.contains(where: { isContained(candidate, by: $0) }) else {
                throw LLMClientError.badResponse("Refused: that folder has not been approved for read access. Request folder access first.")
            }
            return candidate
        }

        if let root = roots.dropFirst().first(where: { root in
            request == root.lastPathComponent || request.hasPrefix(root.lastPathComponent + "/")
        }) {
            let suffix = request == root.lastPathComponent ? "" : String(request.dropFirst(root.lastPathComponent.count + 1))
            return candidateURL(suffix, relativeTo: root)
        }

        return try resolveWorkspace(request, workspace: workspace)
    }

    private static func candidateURL(_ path: String, relativeTo root: URL) -> URL {
        if path.isEmpty || path == "." { return root.standardizedFileURL }
        return URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL
    }

    private static func isContained(_ candidate: URL, by root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path == root.path || candidate.path.hasPrefix(rootPath)
    }
}

enum AgentArtifactPath {
    static func title(from values: [String: JSONValue], fallback: String) -> String {
        let requested = values["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return requested.isEmpty || requested.localizedCaseInsensitiveContains("aura") ? fallback : requested
    }

    static func path(from values: [String: JSONValue], title: String?, fileExtension: String) -> String {
        let requested = values["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard requested.isEmpty || requested.localizedCaseInsensitiveContains("aura") else {
            return URL(fileURLWithPath: requested).pathExtension.isEmpty ? "\(requested).\(fileExtension)" : requested
        }
        return DocumentNaming.filename(title: title ?? "Document", fileExtension: fileExtension)
    }
}

private enum ComputerController {
    static func perform(action: String, value: String, x: Int, y: Int) throws -> String {
        switch action {
        case "open_app":
            let application = URL(fileURLWithPath: "/Applications/\(value).app")
            guard FileManager.default.fileExists(atPath: application.path), NSWorkspace.shared.open(application) else {
                return "Could not open \(value)."
            }
            return "Opened \(value)."
        case "open_url":
            guard let url = URL(string: value), NSWorkspace.shared.open(url) else { return "Could not open the URL." }
            return "Opened \(url.absoluteString)."
        case "click":
            try requireAccessibility()
            let point = CGPoint(x: x, y: y)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            return "Clicked at (\(x), \(y))."
        case "type":
            try requireAccessibility()
            var characters = Array(value.utf16)
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
            up?.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            return "Typed \(characters.count) UTF-16 code units."
        case "key":
            try requireAccessibility()
            guard let key = keyCode(for: value.lowercased()) else { return "Unknown key \(value)." }
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
            return "Pressed \(value)."
        default:
            return "Unknown computer action \(action)."
        }
    }

    private static func requireAccessibility() throws {
        let option = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([option: true] as CFDictionary) else {
            throw LLMClientError.badResponse("Aura needs Accessibility permission before it can click or type. Enable it in System Settings, then retry.")
        }
    }

    private static func keyCode(for key: String) -> CGKeyCode? {
        ["return": 36, "enter": 36, "tab": 48, "escape": 53, "space": 49, "delete": 51][key]
    }
}
