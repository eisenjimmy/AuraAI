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
        XCTAssertEqual(selection.omitted(from: [old, recent]).map(\.id), [old.id])
    }

    func testContinuityFallbackPreservesBothConversationRoles() {
        let user = ConversationMessage(role: .user, content: "We are discussing Cinderella.")
        let friend = ConversationMessage(role: .assistant, content: "The central theme is self-discovery.")

        let fallback = ConversationContinuityWorker.fallback(for: [user, friend])

        XCTAssertTrue(fallback?.contains("User: We are discussing Cinderella.") == true)
        XCTAssertTrue(fallback?.contains("Friend: The central theme is self-discovery.") == true)
    }

    func testWholeShortChatStaysInContext() {
        let first = ConversationMessage(role: .user, content: "Hello")
        let second = ConversationMessage(role: .assistant, content: "Hi")

        let selection = ConversationContextWindow.select(from: [first, second])

        XCTAssertEqual(selection.messages.map(\.id), [first.id, second.id])
        XCTAssertFalse(selection.status.usesRollingWindow)
    }
}
