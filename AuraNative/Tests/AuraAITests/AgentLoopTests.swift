import XCTest
@testable import AuraAI

final class AgentLoopTests: XCTestCase {
    func testSignatureIsStableWhenObjectKeysAreReordered() throws {
        let first = try XCTUnwrap(ToolCall.parse("<tool_call>{\"name\":\"write_file\",\"arguments\":{\"path\":\"notes.md\",\"content\":\"hello\"}}</tool_call>"))
        let second = try XCTUnwrap(ToolCall.parse("<tool_call>{\"name\":\"write_file\",\"arguments\":{\"content\":\"hello\",\"path\":\"notes.md\"}}</tool_call>"))

        XCTAssertEqual(first.signature, second.signature)
    }

    func testLoopGuardAllowsTwoAttemptsThenStopsRepeatedToolCall() throws {
        let call = try XCTUnwrap(ToolCall.parse("<tool_call>{\"name\":\"list_files\",\"arguments\":{\"path\":\".\"}}</tool_call>"))
        var guardrail = AgentLoopGuard()

        XCTAssertTrue(guardrail.allows(call))
        XCTAssertTrue(guardrail.allows(call))
        XCTAssertFalse(guardrail.allows(call))
    }

    func testEventDoesNotExposeRawToolOutput() {
        let execution = ToolExecution(output: String(repeating: "a", count: 600), grantedFolder: nil)
        let event = AgentHarnessEvent.observation(for: execution, step: 1)

        XCTAssertEqual(event.kind, .observation)
        XCTAssertFalse(event.detail.contains(String(repeating: "a", count: 20)))
        XCTAssertTrue(event.title.contains("Step complete") || event.title.contains("단계 완료"))
    }
}
