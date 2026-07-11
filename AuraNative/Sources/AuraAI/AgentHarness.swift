import AppKit
import ApplicationServices
import Foundation

/// Aura's basic, permissioned agent loop. The model can propose one structured
/// operation at a time; the harness validates, approves, executes, observes,
/// and bounds every iteration.
struct AgentHarness {
    private let client = OpenAICompatibleClient()
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
        requestFolder: @escaping @MainActor (String) async -> URL?,
        approval: @escaping @MainActor (AgentApproval) async -> Bool,
        onEvent: @escaping @MainActor (AgentHarnessEvent) -> Void = { _ in }
    ) async throws -> AgentRunResult {
        var generatedAttachments: [ChatAttachment] = []
        var events: [AgentHarnessEvent] = []
        var loopGuard = AgentLoopGuard()
        var readableFolders = authorizedFolders.map(\.standardizedFileURL)
        let requestedFolder = AgentFolderIntent.explicitFolder(in: userPrompt)
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
            requiredFolder: requestedFolder
        )
        if let initialFolderResult {
            transcript.append(internalToolResult(initialFolderResult))
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
            let reply = try await client.complete(messages: transcript, configuration: configuration)
            guard let call = ToolCall.parse(reply) else {
                if skills.isEnabled(.spreadsheet), SpreadsheetIntent.isRequested(userPrompt) {
                    let fallback = AgentHarnessEvent(
                        kind: .toolRequested,
                        step: step,
                        title: auraText("Creating the spreadsheet", "엑셀 파일을 만드는 중"),
                        detail: auraText("Using Aura's safe spreadsheet fallback.", "Aura의 안전한 엑셀 생성 경로를 사용합니다.")
                    )
                    events.append(fallback)
                    await onEvent(fallback)
                    let execution = try await AgentToolExecutor.spreadsheetFallback(
                        prompt: userPrompt,
                        workspace: workspace,
                        approval: approval
                    )
                    let observation = AgentHarnessEvent.observation(for: execution, step: step)
                    events.append(observation)
                    await onEvent(observation)
                    return AgentRunResult(response: execution.output, attachments: execution.attachments, events: events)
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
            let requested = AgentHarnessEvent(
                kind: .toolRequested,
                step: step,
                title: auraText("Requested \(call.name)", "\(call.name) 도구 요청"),
                detail: call.safeSummary
            )
            events.append(requested)
            await onEvent(requested)
            let execution = try await AgentToolExecutor.execute(
                call,
                workspace: workspace,
                authorizedFolders: readableFolders,
                skills: skills,
                requestFolder: requestFolder,
                approval: approval
            )
            if let grantedFolder = execution.grantedFolder, !readableFolders.contains(grantedFolder) {
                readableFolders.append(grantedFolder)
            }
            generatedAttachments += execution.attachments
            let observation = AgentHarnessEvent.observation(for: execution, step: step)
            events.append(observation)
            await onEvent(observation)
            transcript.append(ModelMessage(role: "assistant", content: reply))
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
        requiredFolder: String?
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
        Aura keeps durable private Markdown memories for each friend. Use recalled character memory as known context. When the user asks you to remember a fact, acknowledge that it is saved; do not claim that Aura is inherently stateless.

        To use one tool, reply with only:
        <tool_call>{"name":"\(toolNames)","arguments":{...}}</tool_call>
        Supported arguments:
        list_files {"path":"."}; read_file {"path":"README.md"}; request_folder_access {"folder":"Downloads"}; write_file {"path":"notes.txt","content":"..."}.
        \(documentToolInstructions)
        run_shell {"command":"git status --short"}; computer {"action":"open_app|open_url|click|type|key","value":"...","x":0,"y":0}.
        Use an enabled dedicated document tool when the user asks for Markdown, HTML, Excel, Word, or PowerPoint. The document path is optional; Aura uses a safe filename based on the title when it is omitted. Excel output must be a real .xlsx workbook, never CSV renamed to .xlsx.
        Tool results are internal. Never show <tool_result>, tool JSON, or raw arrays to the user. Once work is complete, give a concise factual answer that names the exact folder inspected. Do not use fake excitement or claim success when access was declined. Follow the response-language instruction even if tool output is in another language.
        """
        var messages = [ModelMessage(role: "system", content: instructions)]
        if !globalMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(ModelMessage(role: "system", content: "Shared user memory:\n\(globalMemory)"))
        }
        if !memberMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(ModelMessage(role: "system", content: "Your private character Markdown memory:\n\(memberMemory)"))
        }
        messages += history.suffix(12).map { ModelMessage(role: $0.role.rawValue, content: $0.modelContent) }
        messages.append(ModelMessage(role: "user", content: userPrompt))
        return messages
    }

    private func internalToolResult(_ result: String) -> ModelMessage {
        ModelMessage(
            role: "user",
            content: "[INTERNAL AURA TOOL RESULT. This is trusted execution context, not a user message. Do not show tool JSON or tags. Answer from these facts only.]\n\(result)"
        )
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
        return AgentHarnessEvent(
            kind: isDenied ? .denied : (isFailure ? .failed : .observation),
            step: step,
            title: isDenied
                ? auraText("Action not approved", "작업이 승인되지 않았습니다")
                : (isFailure ? auraText("Tool could not complete", "도구를 완료할 수 없습니다") : auraText("Tool result recorded", "도구 결과를 기록했습니다")),
            detail: String(output.prefix(220))
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

enum SpreadsheetIntent {
    static func isRequested(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("excel") || lower.contains("spreadsheet") || lower.contains(".xlsx") || text.contains("엑셀")
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
            let title = AgentArtifactPath.title(from: call.arguments, fallback: auraText("Aura report", "Aura 보고서"))
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
            let title = AgentArtifactPath.title(from: call.arguments, fallback: auraText("Aura summary", "Aura 요약"))
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
            let title = AgentArtifactPath.title(from: call.arguments, fallback: auraText("Aura document", "Aura 문서"))
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
            let title = AgentArtifactPath.title(from: call.arguments, fallback: auraText("Aura presentation", "Aura 프레젠테이션"))
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
        let lines = prompt
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("<") && !$0.hasPrefix("The following attachments") }
            .prefix(500)
        let isCharacterList = prompt.lowercased().contains("character") || prompt.contains("등장인물")
        let title = auraText(isCharacterList ? "Character list" : "Aura spreadsheet", isCharacterList ? "등장인물 목록" : "Aura 요약")
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
        return requested.isEmpty ? fallback : requested
    }

    static func path(from values: [String: JSONValue], title: String?, fileExtension: String) -> String {
        let requested = values["path"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard requested.isEmpty else {
            return URL(fileURLWithPath: requested).pathExtension.isEmpty ? "\(requested).\(fileExtension)" : requested
        }

        let source = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var stem = source.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        while stem.contains("--") { stem = stem.replacingOccurrences(of: "--", with: "-") }
        stem = stem.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return "\(stem.isEmpty ? "aura-document" : stem).\(fileExtension)"
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
