import XCTest
@testable import AuraAI

final class ConversationContextTests: XCTestCase {
    func testContextUsesMostRecentMessagesInsideBudget() {
        let old = ConversationMessage(role: .user, content: String(repeating: "old ", count: 8_000), createdAt: .distantPast)
        let recent = ConversationMessage(role: .assistant, content: "Recent Cinderella context", createdAt: .now)

        let selection = ConversationContextWindow.select(from: [old, recent])

        XCTAssertEqual(selection.messages.map(\.id), [recent.id])
        XCTAssertTrue(selection.status.usesRollingWindow)
        XCTAssertEqual(selection.status.includedSince, recent.createdAt)
    }

    func testWholeShortChatStaysInContext() {
        let first = ConversationMessage(role: .user, content: "Hello")
        let second = ConversationMessage(role: .assistant, content: "Hi")

        let selection = ConversationContextWindow.select(from: [first, second])

        XCTAssertEqual(selection.messages.map(\.id), [first.id, second.id])
        XCTAssertFalse(selection.status.usesRollingWindow)
    }
}
