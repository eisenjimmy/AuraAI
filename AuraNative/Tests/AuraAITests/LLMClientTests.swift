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
}
