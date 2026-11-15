import XCTest
@testable import focus

final class FocusTests: XCTestCase {
    func testSmokeBuild() throws {
        XCTAssertTrue(true)
    }

    func testCalendarPolicyDayKeyFormat() {
        // Проверка формата YYYY-MM-DD.
        let key = CalendarPolicy.dayKey(for: .now)
        let pattern = #/^\d{4}-\d{2}-\d{2}$/#
        XCTAssertTrue(key.range(of: pattern) != nil, "dayKey должен быть в формате YYYY-MM-DD, получен: \(key)")
    }
}