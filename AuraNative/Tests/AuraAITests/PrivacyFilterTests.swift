import XCTest
@testable import AuraAI

final class PrivacyFilterTests: XCTestCase {
    func testRedactsAndRestoresCloudSensitiveValues() throws {
        let filter = PrivacyFilter()
        let input = "Email me at hello@example.com or call +1 212-555-0199. token=sk_abcdefghijklmnopqrstuvwxyz"
        let review = try XCTUnwrap(filter.inspect(input, settings: PrivacySettings()))

        XCTAssertFalse(review.redacted.contains("hello@example.com"))
        XCTAssertFalse(review.redacted.contains("212-555-0199"))
        XCTAssertFalse(review.redacted.contains("sk_abcdefghijklmnopqrstuvwxyz"))
        XCTAssertEqual(filter.restore("Received [AURA_EMAIL_1]", review: review), "Received hello@example.com")
    }

    func testDisabledCategoriesDoNotMatch() {
        let filter = PrivacyFilter()
        var settings = PrivacySettings()
        settings.redactEmails = false
        settings.redactPhones = false
        settings.redactCards = false
        settings.redactSecrets = false

        XCTAssertNil(filter.inspect("hello@example.com", settings: settings))
    }
}
