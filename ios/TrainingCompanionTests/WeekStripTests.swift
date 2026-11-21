import SwiftUI
import XCTest
@testable import TrainingCompanion

/// The week strip says in words what its bar says in colour (design-system §6.50).
final class WeekStripTests: XCTestCase {
    private func day(_ sessions: [WeekStrip.Session], _ status: WeekStrip.Status, today: Bool = false) -> WeekStrip.Day {
        var parts = DateComponents(); parts.year = 2026; parts.month = 11; parts.day = 20; parts.hour = 12
        let date = Calendar.current.date(from: parts)!
        return WeekStrip.Day(offset: 0, date: date, status: status, sessions: sessions, isToday: today, isEnabled: true)
    }

    func testADoneDayNamesItsSession() {
        let label = WeekStrip.label(day([.init(color: .yellow, label: "Power")], .done))
        XCTAssertTrue(label.hasSuffix(", Power, done"), label)
    }

    func testTwoSessionsAreBothNamedAndTheSameKindOnce() {
        let two = WeekStrip.label(day([.init(color: .yellow, label: "Power"), .init(color: .teal, label: "Mobility")], .planned, today: true))
        XCTAssertTrue(two.hasSuffix(", Power and Mobility, planned, today"), two)
        let same = WeekStrip.label(day([.init(color: .yellow, label: "Power"), .init(color: .yellow, label: "Power")], .planned))
        XCTAssertTrue(same.hasSuffix(", Power, planned"), same)
    }

    func testARestDayNamesNothing() {
        let label = WeekStrip.label(day([], .rest))
        XCTAssertTrue(label.hasSuffix(", rest"), label)
        XCTAssertFalse(label.contains(", ,"), label)
    }
}
