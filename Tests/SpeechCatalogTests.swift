import XCTest
import SottoCore

final class SpeechCatalogTests: XCTestCase {
    func testCatalogOrderAndKinds() {
        XCTAssertEqual(SpeechCatalog.all.map(\.id), [.parakeetV2, .parakeetUltra, .phonon2, .parakeetV3, .cohere, .appleEnglish])
        XCTAssertEqual(SpeechCatalog.info(.cohere).kind, .cohere)
        XCTAssertFalse(SpeechCatalog.info(.cohere).acceptsHints)
        XCTAssertTrue(SpeechCatalog.info(.appleEnglish).acceptsHints)
        XCTAssertNil(SpeechCatalog.info(.appleEnglish).approximateMegabytes)
        XCTAssertTrue(SpeechCatalog.all.allSatisfy { !$0.credit.isEmpty || $0.kind == .apple })
    }

    func testSpellingLocales() {
        XCTAssertEqual(SpellingVariety.australian.localeIdentifier, "en_AU")
        XCTAssertEqual(SpellingVariety.british.localeIdentifier, "en_GB")
        XCTAssertEqual(SpellingVariety.american.localeIdentifier, "en_US")
    }
}
