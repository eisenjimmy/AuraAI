import Foundation

enum LLMClientError: LocalizedError {
    case invalidEndpoint
    case badResponse(String)
    case missingContent

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "The model endpoint is not a valid URL."
        case .badResponse(let message): return message
        case .missingContent: return "The model returned no message content."
        }
    }
}

struct OpenAICompatibleClient {
    func complete(messages: [ModelMessage], configuration: ProviderConfiguration) async throws -> String {
        guard let url = configuration.chatURL else { throw LLMClientError.invalidEndpoint }
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
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw LLMClientError.badResponse("Model request failed (\(http.statusCode)): \(detail.prefix(600))")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw LLMClientError.missingContent
        }
        return content
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
}
