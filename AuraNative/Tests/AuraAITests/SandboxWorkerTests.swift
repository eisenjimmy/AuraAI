import XCTest
@testable import AuraAI

final class SandboxWorkerTests: XCTestCase {
    func testParsesStrictWorkerVerdicts() {
        XCTAssertEqual(SandboxWorker.parseVerdict(#"{"verdict":"approve","reason":"evidence matches"}"#), .approved)
        XCTAssertEqual(SandboxWorker.parseVerdict(#"{"verdict":"revise","reason":"missing file reference"}"#), .revise("missing file reference"))
        XCTAssertEqual(SandboxWorker.parseVerdict("I think this is good."), .unavailable)
    }

    func testIdentifiesSourceFilesForPrewriteReview() {
        XCTAssertTrue(SandboxWorker.shouldReviewCode(path: "Sources/App.swift"))
        XCTAssertTrue(SandboxWorker.shouldReviewCode(path: "src/main.ts"))
        XCTAssertFalse(SandboxWorker.shouldReviewCode(path: "notes.md"))
    }
}
