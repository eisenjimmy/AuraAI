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
        XCTAssertEqual(vault.recall("Where do I live?").first?.body, "Can you remember that I live in Dix Hills, NY?")
    }

    func testOrdinaryMessagesDoNotBecomeMemories() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = MarkdownMemoryVault(root: root)

        XCTAssertNil(vault.captureIfRequested("What is the weather today?"))
        XCTAssertTrue(vault.list().isEmpty)
    }
}
