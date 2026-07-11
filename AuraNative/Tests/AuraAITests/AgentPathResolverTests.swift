import XCTest
@testable import AuraAI

final class AgentPathResolverTests: XCTestCase {
    func testApprovedFolderCanBeAddressedByName() throws {
        let workspace = URL(fileURLWithPath: "/tmp/aura-workspace")
        let downloads = URL(fileURLWithPath: "/tmp/Downloads")

        let resolved = try AgentPathResolver.resolveReadable(
            "Downloads",
            workspace: workspace,
            authorizedFolders: [downloads]
        )

        XCTAssertEqual(resolved.path, downloads.path)
    }

    func testReadOutsideApprovedRootsIsRejected() {
        XCTAssertThrowsError(
            try AgentPathResolver.resolveReadable(
                "/private/tmp/not-approved",
                workspace: URL(fileURLWithPath: "/tmp/aura-workspace"),
                authorizedFolders: []
            )
        )
    }

    func testWellKnownFolderIntentRecognizesEnglishAndKorean() {
        XCTAssertEqual(AgentFolderIntent.explicitFolder(in: "Can you check my Downloads folder?"), "Downloads")
        XCTAssertEqual(AgentFolderIntent.explicitFolder(in: "다운로드 폴더를 확인해줘"), "Downloads")
        XCTAssertEqual(AgentFolderIntent.explicitFolder(in: "Please inspect my Desktop"), "Desktop")
    }
}
