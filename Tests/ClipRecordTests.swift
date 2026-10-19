import XCTest
@testable import SottoCore

final class ClipRecordTests: XCTestCase {
    private func record(date: Date = Date(timeIntervalSince1970: 0)) -> ClipRecord {
        ClipRecord(date: date, durationSeconds: 1, typingModel: .parakeetV2,
                   rawText: "raw", hintedText: "hinted", typedText: "typed")
    }

    func testRetentionBoundary() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let fresh = record(date: now.addingTimeInterval(-7 * 86_400 + 1))
        let old = record(date: now.addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(ClipRetention.days, 7)
        XCTAssertEqual(ClipRetention.expired([fresh, old], now: now).map(\.id), [old.id])
    }

    func testOldRecordWithoutOptionalFieldsDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":0,"durationSeconds":1.5,"typingModel":"parakeetV2","rawText":"hi","hintedText":"hi","typedText":"Hi."}"#
        let r = try JSONDecoder().decode(ClipRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.modelTexts, [:]); XCTAssertNil(r.pickedModel); XCTAssertNil(r.teacherText)
    }

    func testRoundTrip() throws {
        var r = record()
        r.bundleID = "com.apple.Notes"; r.teacherModel = .cohere; r.teacherText = "t"
        r.modelTexts = ["parakeetV2": "a"]; r.pickedModel = .parakeetV2; r.correctedText = "A."
        let back = try JSONDecoder().decode(ClipRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
    }

    func testTallyCountsPicksAndCorrections() {
        var a = record(); a.modelTexts = ["parakeetV2": "What's up, Madgie?", "parakeetUltra": "What's up, my G?"]; a.pickedModel = .parakeetUltra
        var b = record(); b.modelTexts = ["parakeetV2": "My gee.", "parakeetUltra": "my G"]; b.correctedText = "My G."
        var c = record(); c.modelTexts = ["parakeetV2": "unjudged"]
        let score = CompareScore.tally([a, b, c])
        XCTAssertEqual(score[.parakeetUltra], ModelScore(right: 2, judged: 2))
        XCTAssertEqual(score[.parakeetV2], ModelScore(right: 0, judged: 2))
    }

    func testTallyCountsModelsMatchingThePick() {
        var a = record()
        a.modelTexts = ["parakeetV2": "Hey, my G.", "parakeetUltra": "hey my g", "cohere": "Hey Madgie."]
        a.pickedModel = .parakeetV2
        let before = CompareScore.tally([a])
        XCTAssertEqual(before[.parakeetV2], ModelScore(right: 1, judged: 1))
        XCTAssertEqual(before[.parakeetUltra], ModelScore(right: 1, judged: 1))
        XCTAssertEqual(before[.cohere], ModelScore(right: 0, judged: 1))

        // A model run after the pick that matches it is right too.
        a.modelTexts["phonon2"] = "Hey my G"
        XCTAssertEqual(CompareScore.tally([a])[.phonon2], ModelScore(right: 1, judged: 1))
    }

    func testTallyIgnoresSpellingVariety() {
        var a = record()
        a.modelTexts = ["parakeetV2": "I realize the color is off.", "appleEnglish": "I realise the colour is off", "cohere": "I realise the collar is off."]
        a.pickedModel = .appleEnglish
        var b = record()
        b.modelTexts = ["parakeetV2": "Nice color, my G."]
        b.correctedText = "Nice colour, my G."
        let score = CompareScore.tally([a, b])
        XCTAssertEqual(score[.parakeetV2], ModelScore(right: 2, judged: 2))
        XCTAssertEqual(score[.cohere], ModelScore(right: 0, judged: 1))
    }
}
