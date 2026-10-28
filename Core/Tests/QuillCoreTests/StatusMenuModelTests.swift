import XCTest
@testable import QuillCore

final class StatusMenuModelTests: XCTestCase {
    let clean = Profile(id: "clean", name: "Чистка")
    let raw = Profile(id: "raw", name: "Без обработки", postprocess: false)

    func testIconState() {
        XCTAssertEqual(StatusIcon.make(isRecording: false, activeJobs: 0), .idle)
        XCTAssertEqual(StatusIcon.make(isRecording: false, activeJobs: 2), .processing)
        XCTAssertEqual(StatusIcon.make(isRecording: true, activeJobs: 1), .recording)
    }

    func testStatusLine() {
        XCTAssertEqual(
            StatusMenuModel.statusLine(isRecording: true, activeJobs: 0, activeProfileName: "Чистка"),
            "● Запись… (Esc — отмена)"
        )
        XCTAssertEqual(
            StatusMenuModel.statusLine(isRecording: false, activeJobs: 1, activeProfileName: "Чистка"),
            "Обработка…"
        )
        XCTAssertEqual(
            StatusMenuModel.statusLine(isRecording: false, activeJobs: 0, activeProfileName: "Чистка"),
            "Профиль: Чистка"
        )
    }

    func testItemsLayout() {
        let items = StatusMenuModel.items(
            isRecording: false, activeJobs: 0,
            entries: [.valid(clean), .invalid(id: "broken", message: "Не задано поле name"), .valid(raw)],
            activeProfile: clean
        )
        XCTAssertEqual(items, [
            .status("Профиль: Чистка"),
            .separator,
            .profile(id: "clean", name: "Чистка", isActive: true),
            .profile(id: "raw", name: "Без обработки", isActive: false),
            .invalidProfile("⚠︎ broken.md: Не задано поле name"),
            .separator,
            .action(.history),
            .action(.settings),
            .action(.openProfilesFolder),
            .separator,
            .action(.quit),
        ])
    }

    func testCheckmarkFollowsEffectiveActiveProfile() {
        // Выбранный профиль сломан — фактически работает raw, галочка должна стоять на нём.
        let items = StatusMenuModel.items(
            isRecording: false, activeJobs: 0,
            entries: [.valid(clean), .valid(raw)],
            activeProfile: raw
        )
        XCTAssertTrue(items.contains(.profile(id: "raw", name: "Без обработки", isActive: true)))
        XCTAssertTrue(items.contains(.profile(id: "clean", name: "Чистка", isActive: false)))
    }

    func testNoProfilesSectionStillHasActions() {
        let items = StatusMenuModel.items(isRecording: false, activeJobs: 0, entries: [], activeProfile: .fallbackRaw)
        XCTAssertEqual(items.first, .status("Профиль: Без обработки"))
        XCTAssertEqual(items.last, .action(.quit))
    }
}
