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
        XCTAssertEqual(path, "Aura-summary.xlsx")
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
}
