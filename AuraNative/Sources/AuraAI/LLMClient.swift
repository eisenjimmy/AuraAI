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
    func complete(messages: [ModelMessage], configuration: ProviderConfiguration) async throws -> String {
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
