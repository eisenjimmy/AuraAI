import XCTest
@testable import AuraAI

final class AgentSkillTests: XCTestCase {
    func testDocumentSkillsDefaultToEnabled() {
        let settings = AgentSkillSettings()
        XCTAssertTrue(AgentSkill.allCases.allSatisfy(settings.isEnabled))
    }

    func testDocumentSkillCanBeDisabled() {
        var settings = AgentSkillSettings()
        settings.setEnabled(false, for: .presentation)
        XCTAssertFalse(settings.isEnabled(.presentation))
        XCTAssertTrue(settings.isEnabled(.word))
        XCTAssertEqual(AgentSkill.word.toolName, "create_word_document")
    }
}
