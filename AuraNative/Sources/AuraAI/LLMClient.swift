import Foundation

enum LLMClientError: LocalizedError {
    case invalidEndpoint
    case badResponse(String)
    case missingContent
    case modelStillLoading

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "The model endpoint is not a valid URL."
        case .badResponse(let message): return message
        case .missingContent: return "The model returned no message content."
        case .modelStillLoading:
            return auraText(
                "Your local model is still loading. Aura waited briefly; try again in a few seconds.",
                "로컬 모델을 아직 불러오는 중입니다. Aura가 잠시 기다렸지만 완료되지 않았습니다. 몇 초 뒤 다시 시도하세요."
            )
        }
    }
}

struct OpenAICompatibleClient {
    func stream(
        messages: [ModelMessage],
        configuration: ProviderConfiguration,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        if configuration.kind == .anthropic {
            return try await AnthropicMessagesClient().stream(messages: messages, configuration: configuration, onDelta: onDelta)
        }
        guard let url = configuration.chatURL else { throw LLMClientError.invalidEndpoint }
        for attempt in 0..<5 {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 180
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if configuration.kind.isCloud, !configuration.apiKey.isEmpty {
                request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONEncoder().encode(ChatRequest(model: configuration.model, messages: messages, stream: true))

            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMClientError.badResponse("The model endpoint did not return HTTP.")
            }
            guard (200..<300).contains(http.statusCode) else {
                let data = try await Self.collect(bytes)
                if http.statusCode == 503, Self.isModelLoading(data), attempt < 4 {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                if http.statusCode == 503, Self.isModelLoading(data) {
                    throw LLMClientError.modelStillLoading
                }
                let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw LLMClientError.badResponse("Model request failed (\(http.statusCode)): \(detail.prefix(600))")
            }

            var result = ""
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard payload != "[DONE]", let delta = Self.streamDelta(from: Data(payload.utf8)) else { continue }
                result += delta
                await onDelta(delta)
            }
            guard !result.isEmpty else { throw LLMClientError.missingContent }
            return result
        }
        throw LLMClientError.modelStillLoading
    }

    func complete(messages: [ModelMessage], configuration: ProviderConfiguration) async throws -> String {
        if configuration.kind == .anthropic {
            return try await AnthropicMessagesClient().complete(messages: messages, configuration: configuration)
        }
        guard let url = configuration.chatURL else { throw LLMClientError.invalidEndpoint }
        for attempt in 0..<5 {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 180
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if configuration.kind.isCloud, !configuration.apiKey.isEmpty {
                request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONEncoder().encode(ChatRequest(model: configuration.model, messages: messages, stream: false))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMClientError.badResponse("The model endpoint did not return HTTP.")
            }
            if (200..<300).contains(http.statusCode) {
                let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
                guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
                    throw LLMClientError.missingContent
                }
                return content
            }
            if http.statusCode == 503, Self.isModelLoading(data), attempt < 4 {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }
            if http.statusCode == 503, Self.isModelLoading(data) {
                throw LLMClientError.modelStillLoading
            }
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw LLMClientError.badResponse("Model request failed (\(http.statusCode)): \(detail.prefix(600))")
        }
        throw LLMClientError.modelStillLoading
    }

    static func isModelLoading(_ data: Data) -> Bool {
        let value = String(data: data, encoding: .utf8)?.lowercased() ?? ""
        return value.contains("loading model") || value.contains("model is loading")
    }

    static func streamDelta(from data: Data) -> String? {
        let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data)
        return chunk?.choices.first?.delta.content
    }

    private static func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        return data
    }

    private struct ChatRequest: Encodable {
        var model: String
        var messages: [ModelMessage]
        var stream: Bool
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct ResponseMessage: Decodable { var content: String? }
            var message: ResponseMessage
        }
        var choices: [Choice]
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { var content: String? }
            var delta: Delta
        }
        var choices: [Choice]
    }
}

private struct AnthropicMessagesClient {
    func stream(
        messages: [ModelMessage],
        configuration: ProviderConfiguration,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard configuration.messagesURL != nil else { throw LLMClientError.invalidEndpoint }
        let request = request(messages: messages, configuration: configuration, streaming: true)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMClientError.badResponse("The Claude endpoint did not return HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let data = try await collect(bytes)
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw LLMClientError.badResponse("Model request failed (\(http.statusCode)): \(detail.prefix(600))")
        }

        var result = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let event = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: Data(payload.utf8)),
                  event.type == "content_block_delta",
                  let delta = event.delta?.text,
                  !delta.isEmpty else { continue }
            result += delta
            await onDelta(delta)
        }
        guard !result.isEmpty else { throw LLMClientError.missingContent }
        return result
    }

    func complete(messages: [ModelMessage], configuration: ProviderConfiguration) async throws -> String {
        guard configuration.messagesURL != nil else { throw LLMClientError.invalidEndpoint }
        let request = request(messages: messages, configuration: configuration, streaming: false)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMClientError.badResponse("The Claude endpoint did not return HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw LLMClientError.badResponse("Model request failed (\(http.statusCode)): \(detail.prefix(600))")
        }
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let content = decoded.content.compactMap(\.text).joined(separator: "\n")
        guard !content.isEmpty else { throw LLMClientError.missingContent }
        return content
    }

    private func request(messages: [ModelMessage], configuration: ProviderConfiguration, streaming: Bool) -> URLRequest {
        let system = messages
            .filter { $0.role == "system" }
            .map(\.content)
            .joined(separator: "\n\n")
        let conversation = messages
            .filter { $0.role != "system" }
            .map(AnthropicMessage.init)
        var request = URLRequest(url: configuration.messagesURL!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONEncoder().encode(AnthropicRequest(
            model: configuration.model,
            maxTokens: 4_096,
            system: system.isEmpty ? nil : system,
            messages: conversation,
            stream: streaming
        ))
        return request
    }

    private func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        return data
    }

    private struct AnthropicRequest: Encodable {
        var model: String
        var maxTokens: Int
        var system: String?
        var messages: [AnthropicMessage]
        var stream: Bool

        private enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
            case stream
        }
    }

    private struct AnthropicMessage: Encodable {
        var role: String
        var content: [ContentBlock]

        init(_ message: ModelMessage) {
            role = message.role == "assistant" ? "assistant" : "user"
            content = [.text(message.content)] + message.imageURLs.compactMap(ContentBlock.image)
        }
    }

    private struct ContentBlock: Encodable {
        var type: String
        var text: String?
        var source: ImageSource?

        static func text(_ value: String) -> Self {
            Self(type: "text", text: value, source: nil)
        }

        static func image(_ dataURL: String) -> Self? {
            guard let comma = dataURL.firstIndex(of: ",") else { return nil }
            let metadata = String(dataURL[..<comma])
            let data = String(dataURL[dataURL.index(after: comma)...])
            guard metadata.hasPrefix("data:"), metadata.contains(";base64"), !data.isEmpty else { return nil }
            let mediaType = metadata
                .replacingOccurrences(of: "data:", with: "")
                .replacingOccurrences(of: ";base64", with: "")
            return Self(type: "image", text: nil, source: ImageSource(type: "base64", mediaType: mediaType, data: data))
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case source
        }
    }

    private struct ImageSource: Encodable {
        var type: String
        var mediaType: String
        var data: String

        private enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }
    }

    private struct AnthropicResponse: Decodable {
        struct Content: Decodable {
            var type: String
            var text: String?
        }

        var content: [Content]
    }

    private struct AnthropicStreamEvent: Decodable {
        struct Delta: Decodable { var text: String? }
        var type: String
        var delta: Delta?
    }
}
