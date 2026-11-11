import Foundation
import Core
import XCTest

final class SelectionConversionTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")
    private let zone = TimeZone(identifier: "Asia/Kolkata")!
    private let now = Date(timeIntervalSince1970: 1_794_398_400)

    func testCurrencySymbolsCodesAndNumberFormats() {
        XCTAssertEqual(detect("$"), .currency(amount: 1, source: "USD", target: "INR"))
        XCTAssertEqual(detect("USD"), .currency(amount: 1, source: "USD", target: "INR"))
        XCTAssertEqual(detect("The total is $100 USD."), .currency(amount: 100, source: "USD", target: "INR"))
        XCTAssertEqual(detect("₹1,25,000"), .currency(amount: 125000, source: "INR", target: "USD"))
        XCTAssertEqual(detect("1.234,56 EUR"), .currency(amount: 1234.56, source: "EUR", target: "INR"))
        XCTAssertNil(detect("Compare $10 and €20"))
    }

    func testTimeUsesTheConfiguredDestinationAndIncludesDayRollover() {
        XCTAssertTrue(clock("2026-11-11 3:50 berlin time")?.contains("8:20 AM IST") == true)
        XCTAssertTrue(clock("09:00 UTC")?.contains("2:30 PM IST") == true)
        XCTAssertTrue(clock("UTC")?.hasSuffix(" GMT") == true)
        XCTAssertTrue(clock("2026-11-11 11:45 PM PST")?.contains("Nov 12") == true)
        XCTAssertNil(detect("25:15 UTC"))
    }

    func testTimeRecognizesCitiesFromTheTimeZoneDatabase() {
        XCTAssertTrue(clock("03:13 dubai time")?.contains("4:43 AM IST") == true)
        XCTAssertTrue(clock("09:00 Tokyo time")?.contains("5:30 AM IST") == true)
        XCTAssertEqual(detect("03:13 Cambridge time"), .cityTime(clock: "03:13", city: "Cambridge"))
        XCTAssertNil(detect("25:15 Dubai time"))
    }

    func testMeasurementDimensionsDataAndColor() {
        XCTAssertEqual(detect("5 × 7 in"), .measurement("12.7 × 17.78 cm"))
        XCTAssertEqual(detect("12 pt"), .measurement("16 px"))
        XCTAssertEqual(detect("72°F"), .measurement("22.222 °C"))
        XCTAssertEqual(detect("2 GB"), .measurement("1.863 GiB"))
        XCTAssertEqual(detect("#F80"), .color(InlineColor(hex: "#F80")!))
    }

    func testCompactMultiplicationWithoutUnits() {
        XCTAssertEqual(CalculateAction().evaluateSynchronously("4829x10310"), "49786990")
        XCTAssertEqual(CalculateAction().evaluateSynchronously("8X7"), "56")
        XCTAssertNil(CalculateAction().evaluateSynchronously("5x7 in"))
    }

    func testLanguageDetectionWithoutAnAIProvider() {
        let german = "Starte jetzt dein Studium an einer staatlich anerkannten, privaten Hochschule in Deutschland."
        XCTAssertEqual(TextLanguageDetector.translationSource(for: german), "de")
        XCTAssertNil(TextLanguageDetector.translationSource(for: "The article describes a new discovery."))
        XCTAssertNil(TextLanguageDetector.translationSource(for: "$1,200 USD"))
    }

    private func detect(_ text: String) -> SelectionConversion? {
        SelectionConversion.detect(text, timeZone: zone, now: now, locale: locale)
    }

    private func clock(_ text: String) -> String? {
        guard case .time(let value) = detect(text) else { return nil }
        return value.replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
