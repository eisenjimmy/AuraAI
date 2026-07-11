import AppKit
import ApplicationServices
import Foundation

/// A deliberately small agent protocol. The model may request one operation in
/// a tagged JSON block; Aura owns parsing, scope checks, approval, execution,
/// and the iteration cap.
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
        requestFolder: @escaping @MainActor (String) async -> URL?,
        approval: @escaping @MainActor (AgentApproval) async -> Bool
    ) async throws -> AgentRunResult {
        var generatedAttachments: [ChatAttachment] = []
        var readableFolders = authorizedFolders.map(\.standardizedFileURL)
        let requestedFolder = AgentFolderIntent.explicitFolder(in: userPrompt)
        var initialFolderResult: String?

        // A clear request for a well-known user folder is an explicit user
        // intent. Ask the user to select it before a fallible model can fall
        // back to listing the unrelated workspace.
        if let requestedFolder,
           !readableFolders.contains(where: { $0.lastPathComponent.caseInsensitiveCompare(requestedFolder) == .orderedSame }) {
            guard let grantedFolder = await requestFolder(requestedFolder) else {
                return AgentRunResult(response: "I couldn't inspect \(requestedFolder) because folder access was not granted.", attachments: [])
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
            requiredFolder: requestedFolder
        )
        if let initialFolderResult {
            transcript.append(internalToolResult(initialFolderResult))
        }

        for _ in 0..<maximumSteps {
            let reply = try await client.complete(messages: transcript, configuration: configuration)
            guard let call = ToolCall.parse(reply) else {
                return AgentRunResult(response: reply, attachments: generatedAttachments)
            }
            let execution = try await AgentToolExecutor.execute(
                call,
                workspace: workspace,
                authorizedFolders: readableFolders,
                requestFolder: requestFolder,
                approval: approval
            )
            if let grantedFolder = execution.grantedFolder, !readableFolders.contains(grantedFolder) {
                readableFolders.append(grantedFolder)
            }
            generatedAttachments += execution.attachments
            transcript.append(ModelMessage(role: "assistant", content: reply))
            transcript.append(internalToolResult(execution.output))
        }
        return AgentRunResult(
            response: "I stopped after \(maximumSteps) tool steps. The work may be incomplete; review the activity and continue with a more specific instruction.",
            attachments: generatedAttachments
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
        requiredFolder: String?
    ) -> [ModelMessage] {
        let workspaceDescription = workspace?.path ?? "No workspace selected. Do not request file or shell tools."
        let folderDescription = authorizedFolders.isEmpty
            ? "No extra folders have been approved."
            : authorizedFolders.map(\.path).joined(separator: ", ")
        let targetInstruction = requiredFolder.map {
            "The current request explicitly targets the approved \($0) folder. Report only what the internal folder result confirms."
        } ?? ""
        let instructions = """
        \(AuraEdition.current.responseLanguageInstruction)

        \(member.systemPrompt)

        You are operating inside Aura's permissioned agent harness. Selected workspace: \(workspaceDescription)
        Additional approved read-only folders: \(folderDescription)
        \(targetInstruction)
        You may inspect the selected workspace and only the additional folders above with list_files and read_file. You cannot see Downloads, Desktop, Documents, or any other folder unless it is explicitly approved. If the user asks about one of those folders, call request_folder_access first. Do not substitute the workspace for the requested folder.
        File writes and shell commands remain limited to the selected workspace. Computer control requires visible user approval. Never claim you saw, read, or changed anything unless a tool result confirms the exact target.

        To use one tool, reply with only:
        <tool_call>{"name":"list_files|read_file|request_folder_access|write_file|create_markdown_document|create_html_document|create_spreadsheet|run_shell|computer","arguments":{...}}</tool_call>
        Supported arguments:
        list_files {"path":"."}; read_file {"path":"README.md"}; request_folder_access {"folder":"Downloads"}; write_file {"path":"notes.txt","content":"..."}.
        create_markdown_document {"path":"report.md","content":"# Report\n..."}.
        create_html_document {"path":"report.html","title":"Report","summary":"One-line summary","body_html":"<section><h2>Findings</h2><p>...</p></section>"}.
        create_spreadsheet {"path":"report.xlsx","sheet":"Summary","title":"Report","headers":["Item","Amount"],"rows":[["Example",1250],["Active",true]]}.
        run_shell {"command":"git status --short"}; computer {"action":"open_app|open_url|click|type|key","value":"...","x":0,"y":0}.
        Use the dedicated document tools when the user asks for Markdown, HTML, or Excel. Excel output must be a real .xlsx workbook, never CSV renamed to .xlsx.
        Tool results are internal. Never show <tool_result>, tool JSON, or raw arrays to the user. Once work is complete, give a concise factual answer that names the exact folder inspected. Do not use fake excitement or claim success when access was declined. Follow the response-language instruction even if tool output is in another language.
        """
        var messages = [ModelMessage(role: "system", content: instructions)]
        if !globalMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(ModelMessage(role: "system", content: "Shared user memory:\n\(globalMemory)"))
        }
        if !memberMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(ModelMessage(role: "system", content: "Your private character memory:\n\(memberMemory)"))
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

struct ToolCall: Decodable {
    var name: String
    var arguments: [String: JSONValue]

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
}

private struct ToolExecution {
    var output: String
    var grantedFolder: URL?
    var attachments: [ChatAttachment] = []
}

private enum AgentToolExecutor {
    static func execute(
        _ call: ToolCall,
        workspace: URL?,
        authorizedFolders: [URL],
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
            let path = try required("path", call.arguments)
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
            let path = try required("path", call.arguments)
            let title = try required("title", call.arguments)
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
            let path = try required("path", call.arguments)
            let title = try required("title", call.arguments)
            let sheet = call.arguments["sheet"]?.stringValue ?? "Summary"
            let headers = try requiredArray("headers", call.arguments).compactMap(\.stringValue)
            let rows = try requiredArray("rows", call.arguments).compactMap(\.arrayValue)
            let file = try AgentPathResolver.resolveWorkspace(path, workspace: workspace)
            let allowed = await approval(AgentApproval(
                kind: .writeFile,
                title: "Create \(file.lastPathComponent)",
                detail: "\(title)\n\(headers.joined(separator: " | "))\n\(rows.count) data rows"
            ))
            guard allowed else { return ToolExecution(output: "User declined the Excel workbook write.", grantedFolder: nil) }
            try ArtifactWriter.spreadsheet(title: title, sheetName: sheet, headers: headers, rows: rows, to: file)
            return ToolExecution(output: "Created Excel workbook at \(path) with \(rows.count) data rows.", grantedFolder: nil, attachments: [generatedAttachment(file, kind: "Excel workbook")])
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

    private static func requiredArray(_ key: String, _ values: [String: JSONValue]) throws -> [JSONValue] {
        guard let value = values[key]?.arrayValue else {
            throw LLMClientError.badResponse("Tool requires a \(key) array.")
        }
        return value
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
