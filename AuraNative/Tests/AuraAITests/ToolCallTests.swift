import XCTest
@testable import AuraAI

final class ToolCallTests: XCTestCase {
    func testParsesDocumentedArgumentsEnvelope() throws {
        let call = try XCTUnwrap(ToolCall.parse("<tool_call>{\"name\":\"create_spreadsheet\",\"arguments\":{\"path\":\"friends.xlsx\",\"headers\":[\"Name\"]}}</tool_call>"))
        XCTAssertEqual(call.name, "create_spreadsheet")
        XCTAssertEqual(call.arguments["path"]?.stringValue, "friends.xlsx")
    }

    func testParsesFlatLocalModelToolCall() throws {
        let call = try XCTUnwrap(ToolCall.parse("<tool_call>{\"name\":\"create_spreadsheet\",\"path\":\"friends.xlsx\",\"sheet\":\"List\",\"headers\":[\"Name\"],\"rows\":[[\"Hana\"]]}</tool_call>"))
        XCTAssertEqual(call.name, "create_spreadsheet")
        XCTAssertEqual(call.arguments["path"]?.stringValue, "friends.xlsx")
        XCTAssertEqual(call.arguments["rows"]?.arrayValue?.count, 1)
    }

    func testRecoversFlatToolCallWithoutClosingTag() throws {
        let response = """
        <tool_call>{"name":"create_spreadsheet","path":"cinderella_cast.xlsx","sheet":"Characters","title":"Cinderella Characters by Perrault","headers":["Name","Role/Relation"],"rows":[["Cinderella","Protagonist"],["Two Stepsisters",["Eldest","Jeering"],"Younger",["Less rude","Dismissive"]]]}%
        """
        let call = try XCTUnwrap(ToolCall.parse(response))
        XCTAssertEqual(call.name, "create_spreadsheet")
        XCTAssertEqual(call.arguments["path"]?.stringValue, "cinderella_cast.xlsx")
        XCTAssertEqual(call.arguments["rows"]?.arrayValue?.count, 2)
    }

    func testArtifactPathDefaultsFromTitleWhenToolOmitsPath() {
        let path = AgentArtifactPath.path(from: [:], title: "Cinderella Characters", fileExtension: "xlsx")
        XCTAssertEqual(path, "Cinderella-Characters.xlsx")
    }

    func testArtifactPathUsesSafeFallbackForBlankPathAndTitle() {
        let values: [String: JSONValue] = ["path": .string("   "), "title": .string("   ")]
        let title = AgentArtifactPath.title(from: values, fallback: "Aura summary")
        let path = AgentArtifactPath.path(from: values, title: title, fileExtension: "xlsx")
        XCTAssertEqual(title, "Aura summary")
        XCTAssertEqual(path, "summary.xlsx")
    }

    func testRecognizesKoreanSpreadsheetIntent() {
        XCTAssertTrue(SpreadsheetIntent.isRequested("이 PDF를 엑셀로 정리해줘"))
        XCTAssertTrue(SpreadsheetIntent.isRequested("Create an Excel workbook"))
        XCTAssertFalse(SpreadsheetIntent.isRequested("Explain this document"))
    }

    func testPresentationTakesPrecedenceOverSpreadsheetSourceMaterial() {
        XCTAssertEqual(
            ArtifactIntent.requested(in: "Make a PowerPoint from this Excel workbook."),
            .presentation
        )
        XCTAssertEqual(
            ArtifactIntent.requested(in: "이 엑셀 자료로 파워포인트 슬라이드를 만들어줘"),
            .presentation
        )
        XCTAssertTrue(ArtifactIntent.presentation.conflicts(with: "create_spreadsheet"))
        XCTAssertFalse(ArtifactIntent.presentation.conflicts(with: "create_presentation"))
    }

    func testDocumentTitleUsesPriorSourceContext() {
        XCTAssertEqual(
            DocumentNaming.suggestedTitle(for: .presentation, source: "Cinderella is the protagonist of this tale.\nThe stepsisters are antagonists."),
            "Cinderella Presentation"
        )
        XCTAssertEqual(DocumentNaming.filename(title: "Aura Presentation", fileExtension: "pptx"), "Presentation.pptx")
    }

    func testSavedRawToolProtocolIsNeverRenderedOrReusedAsConversationText() {
        let raw = """
        I will make the workbook now.
        <tool_call>{\"name\":\"create_spreadsheet\",\"path\":\"cinderella.xlsx\",\"rows\":[[\"Cinderella\",\"Protagonist\"]]}%```
        The workbook was saved.
        """
        let message = ConversationMessage(role: .assistant, content: raw)
        XCTAssertTrue(ToolProtocolSanitizer.containsToolCall(in: raw))
        XCTAssertFalse(message.displayContent.contains("<tool_call"))
        XCTAssertFalse(message.modelContent.contains("<tool_call"))
        XCTAssertTrue(message.displayContent.contains("완료되지") || message.displayContent.contains("did not complete"))
    }

    func testSavedToolResultIsNeverRenderedOrReusedAsConversationText() {
        let raw = "<tool_result>{\"files\":[\"notes.md\"]}</tool_result>"
        let message = ConversationMessage(role: .assistant, content: raw)
        XCTAssertTrue(ToolProtocolSanitizer.containsInternalProtocol(in: raw))
        XCTAssertFalse(message.displayContent.contains("<tool_result"))
        XCTAssertFalse(message.modelContent.contains("<tool_result"))
    }
}
