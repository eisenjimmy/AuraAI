import XCTest
@testable import AuraAI

final class LLMClientTests: XCTestCase {
    func testRecognizesLoadingModelResponse() {
        XCTAssertTrue(OpenAICompatibleClient.isModelLoading(Data("{\"error\":{\"message\":\"Loading model\"}}".utf8)))
        XCTAssertTrue(OpenAICompatibleClient.isModelLoading(Data("model is loading".utf8)))
        XCTAssertFalse(OpenAICompatibleClient.isModelLoading(Data("unknown model".utf8)))
    }

    func testKoreanEditionInstructionRequiresKoreanReply() {
        XCTAssertTrue(AuraEdition.korean.responseLanguageInstruction.contains("항상 자연스럽고 완전한 한국어"))
    }

    func testMultimodalMessageUsesOpenAIImageParts() throws {
        let message = ModelMessage(
            role: "user",
            content: "Describe the image.",
            imageURLs: ["data:image/png;base64,AA=="]
        )
        let data = try JSONEncoder().encode([message])
        let objects = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let content = try XCTUnwrap(objects.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[1]["type"] as? String, "image_url")
        XCTAssertEqual((content[1]["image_url"] as? [String: String])?["url"], "data:image/png;base64,AA==")
    }

    func testCloudProviderPresetsExposeEndpointAndModels() {
        XCTAssertEqual(ProviderKind.openAI.defaultBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(ProviderKind.anthropic.defaultBaseURL, "https://api.anthropic.com/v1")
        XCTAssertEqual(ProviderKind.gemini.defaultBaseURL, "https://generativelanguage.googleapis.com/v1beta/openai")
        XCTAssertEqual(ProviderKind.grok.defaultBaseURL, "https://api.x.ai/v1")
        XCTAssertTrue(ProviderKind.anthropic.modelOptions.contains("claude-sonnet-5"))
        XCTAssertTrue(ProviderKind.gemini.modelOptions.contains("gemini-3.5-flash"))
        XCTAssertTrue(ProviderKind.openAI.modelOptions.contains("gpt-5-mini"))
        XCTAssertTrue(ProviderKind.grok.modelOptions.contains("grok-4.3"))
    }

    func testClaudeMessagesURLUsesMessagesRoute() {
        var configuration = ProviderConfiguration()
        configuration.kind = .anthropic
        configuration.baseURL = ProviderKind.anthropic.defaultBaseURL
        XCTAssertEqual(configuration.messagesURL?.absoluteString, "https://api.anthropic.com/v1/messages")
    }
}
