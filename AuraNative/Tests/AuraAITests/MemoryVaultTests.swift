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

    func testCuratorRejectsTaskMetadataAndKeepsCinderellaContent() {
        let reply = """
        {"facts":[
          {"text":"요청자는 '신데렐라' 이야기의 내용을 요약하는 작업을 진행했음.","retention":"long_term"},
          {"text":"신데렐라는 계모와 의붓자매들에게 학대받지만 요정 대모의 도움으로 무도회에 간다.","retention":"long_term"},
          {"text":"자정에 마법이 풀리며 남겨진 유리구두가 왕자와 신데렐라를 다시 이어 준다.","retention":"long_term"}
        ]}
        """

        let candidates = MemorySubagent.parse(reply: reply, excluding: "신데렐라 스토리도 기억해줘")

        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(candidates.allSatisfy { !$0.text.contains("요청자") && !$0.text.contains("작업") })
        XCTAssertTrue(candidates.contains { $0.text.contains("유리구두") })
    }

    func testCompletedMemorySummaryKeepsImmediateClarificationAttachedToOriginalRequest() {
        let conversation = [
            ConversationMessage(role: .user, content: "오늘 얘기한 거 기억해줘"),
            ConversationMessage(role: .assistant, content: "무엇을 중심으로 기억할까?"),
            ConversationMessage(role: .user, content: "야구 본 거랑 스파게티 먹은 거 말이야")
        ]
        let response = "**핵심** **기억** **사항:** 네가 오늘 야구도 봤고, 저녁으로 스파게티를 먹었다는 거."

        let request = MemorySubagent.resolvedCaptureRequest(
            currentRequest: conversation.last!.content,
            conversation: conversation,
            completedResponse: response
        )

        XCTAssertNotNil(request)
        XCTAssertTrue(request!.contains("오늘 얘기한 거 기억해줘"))
        XCTAssertTrue(request!.contains("야구 본 거랑 스파게티"))
    }

    func testOrdinaryResponseDoesNotReopenAnEarlierMemoryRequest() {
        let conversation = [
            ConversationMessage(role: .user, content: "오늘 얘기한 거 기억해줘"),
            ConversationMessage(role: .assistant, content: "알겠어."),
            ConversationMessage(role: .user, content: "내일 날씨는 어때?")
        ]

        XCTAssertNil(MemorySubagent.resolvedCaptureRequest(
            currentRequest: conversation.last!.content,
            conversation: conversation,
            completedResponse: "내일은 맑을 것 같아."
        ))
    }

    func testKoreanSubjectParticleMatchesFinalConsonant() {
        XCTAssertEqual(koreanSubject("하나"), "하나가")
        XCTAssertEqual(koreanSubject("은별"), "은별이")
    }

    func testMemoryCuratorRequiresTheEditionLanguage() {
        let korean = MemorySubagent.outputLanguageInstruction(for: .korean)
        let english = MemorySubagent.outputLanguageInstruction(for: .english)

        XCTAssertTrue(korean.contains("MUST be written in natural Korean"))
        XCTAssertTrue(korean.contains("Translate supported English"))
        XCTAssertTrue(english.contains("MUST be written in natural English"))
    }

    func testCuratorEvidenceUsesRollingContextAndAttachmentContents() {
        let attachment = ChatAttachment(
            fileName: "cinderella.md",
            storedPath: "/tmp/cinderella.md",
            kind: "Markdown",
            extractedText: "신데렐라는 자정 전에 무도회를 떠나며 유리구두 한 짝을 남긴다.",
            warning: nil
        )
        let conversation = [
            ConversationMessage(role: .assistant, content: String(repeating: "old context ", count: 2_000)),
            ConversationMessage(role: .user, content: "이 문서의 이야기를 기억해줘", attachments: [attachment])
        ]

        let evidence = MemorySubagent.evidence(from: conversation, tokenBudget: 1_000)

        XCTAssertFalse(evidence.transcript.contains("old context"))
        XCTAssertTrue(evidence.transcript.contains("유리구두"))
        XCTAssertTrue(evidence.transcript.contains("cinderella.md"))
        XCTAssertLessThanOrEqual(ConversationContextWindow.estimatedTokens(evidence.transcript), 1_025)
    }

    func testCuratorEvidencePassesAnAttachedImageToVisionModel() throws {
        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: imageURL) }
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        let attachment = ChatAttachment(
            fileName: "story.png",
            storedPath: imageURL.path,
            kind: "Image",
            extractedText: "[Visual image attached.]",
            warning: nil
        )

        let evidence = MemorySubagent.evidence(from: [
            ConversationMessage(role: .user, content: "Remember the story in this image.", attachments: [attachment])
        ])

        XCTAssertEqual(evidence.imageURLs.count, 1)
        XCTAssertTrue(evidence.imageURLs[0].hasPrefix("data:image/png;base64,"))
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
