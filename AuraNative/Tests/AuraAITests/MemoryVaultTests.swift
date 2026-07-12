import XCTest
@testable import AuraAI

final class MemoryVaultTests: XCTestCase {
    func testExplicitMemoryRequestCreatesObsidianNoteAndRecallsIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = MarkdownMemoryVault(root: root)

        let saved = vault.captureIfRequested("Can you remember that I live in Dix Hills, NY?")

        XCTAssertNotNil(saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("MEMORY.md").path))
        XCTAssertEqual(vault.list().count, 1)
        XCTAssertEqual(vault.recall("Where do I live?").first?.body, "I live in Dix Hills, NY")
    }

    func testOrdinaryMessagesDoNotBecomeMemories() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = MarkdownMemoryVault(root: root)

        XCTAssertNil(vault.captureIfRequested("What is the weather today?"))
        XCTAssertTrue(vault.list().isEmpty)
    }

    func testConversationLevelMemoryRequestIsNotSavedLiterally() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = MarkdownMemoryVault(root: root)

        XCTAssertNil(vault.captureIfRequested("우리가 대화한 내용을 바탕으로 기억해줘"))
        XCTAssertTrue(vault.list().isEmpty)
    }

    func testExpiringMemoryStoresExpirationMetadata() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = MarkdownMemoryVault(root: root)

        let note = vault.save(body: "Use the temporary project name this week.", retention: .sevenDays)

        XCTAssertNotNil(note.expiresAt)
        XCTAssertNotNil(vault.list().first?.expiresAt)
    }
}
