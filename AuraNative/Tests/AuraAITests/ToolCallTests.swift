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
}
