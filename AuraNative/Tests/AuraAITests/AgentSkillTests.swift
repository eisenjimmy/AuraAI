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

    func testFriendSkillDefaultsToEnabled() {
        let member = TeamMember.defaults[0]
        XCTAssertTrue(AgentSkill.allCases.allSatisfy(member.isSkillEnabled))
    }

    func testFriendSkillsCannotExpandGlobalSkills() {
        var global = AgentSkillSettings()
        global.setEnabled(false, for: .presentation)
        var member = TeamMember.defaults[0]
        member.setSkillEnabled(false, for: .word)

        let effective = global.limited(to: member)

        XCTAssertFalse(effective.isEnabled(.presentation))
        XCTAssertFalse(effective.isEnabled(.word))
        XCTAssertTrue(effective.isEnabled(.spreadsheet))
    }

    func testDefaultTeamIncludesFamilyDoctor() {
        let doctor = TeamMember.defaults.first { $0.role == .familyDoctor }
        XCTAssertEqual(doctor?.name, "Dr. Maya")
        XCTAssertTrue(doctor?.systemPrompt.contains("family-medicine") ?? false)
    }
}
