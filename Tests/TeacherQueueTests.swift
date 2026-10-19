import XCTest
@testable import SottoCore

final class TeacherQueueTests: XCTestCase {
    private func record(at seconds: TimeInterval, typedBy model: SpeechModelID = .parakeetV2,
                        teacherText: String? = nil) -> ClipRecord {
        ClipRecord(date: Date(timeIntervalSince1970: seconds), durationSeconds: 1, typingModel: model,
                   rawText: "raw", hintedText: "raw", typedText: "Raw.", teacherText: teacherText)
    }

    func testPendingIsOldestFirstAndSkipsCheckedAndTeacherTypedClips() {
        let newer = record(at: 200)
        let older = record(at: 100)
        let checked = record(at: 50, teacherText: "done")
        let unusable = record(at: 60, teacherText: "")
        let byTeacher = record(at: 70, typedBy: .cohere)
        let pending = TeacherQueue.pending([newer, checked, unusable, byTeacher, older], teacher: .cohere)
        XCTAssertEqual(pending.map(\.id), [older.id, newer.id])
    }

    func testPendingLeavesOutSkippedClips() {
        let a = record(at: 1)
        let b = record(at: 2)
        XCTAssertEqual(TeacherQueue.pending([a, b], teacher: .cohere, skipping: [a.id]).map(\.id), [b.id])
    }

    func testIdleAfterFiveMinutesWithoutDictation() {
        let last = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(TeacherQueue.idleSeconds, 300)
        XCTAssertFalse(TeacherQueue.isIdle(lastDictation: last, now: last.addingTimeInterval(299)))
        XCTAssertTrue(TeacherQueue.isIdle(lastDictation: last, now: last.addingTimeInterval(300)))
    }

    func testSubstitutionsIgnoreSpellingVariety() {
        var clip = record(at: 0)
        clip.rawText = "What's up Madgie, nice colour"
        let found = TeacherQueue.substitutions(in: clip, teacherText: "What's up, my G? Nice color.")
        XCTAssertEqual(found.map(\.written), ["my G"])
    }
}
