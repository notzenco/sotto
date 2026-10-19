# Accent and Slang Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the owner choose and compare local speech models on their own voice, teach the fast typing model their words through hint words learned from their fixes, Compare picks and a background teacher model, and add Australian/British/American spelling with swearing kept as said.

**Architecture:** Pure logic goes in `SottoCore` (Foundation only) with XCTest coverage: the model catalog, settings fields, spelling conversion, clip records and retention, phrase alignment, fix detection, sound-alike matching and the learned-word lexicon. The app gets a `Speech/` folder with one `SpeechEngine` protocol and engines for the Parakeet family, Cohere Transcribe and Apple's transcriber, coordinated by a `ModelLibrary`. A `ClipStore` keeps audio, a `FixWatcher` reads fields back after insertion, and a `TeacherScheduler` runs the teacher when idle on mains power. Settings gains model, teacher, spelling and compare rows; Dictionary gains Learned and Your words; a new Compare window scores models.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Accessibility (AX), FluidAudio (Parakeet TDT, Cohere Transcribe, CTC vocabulary boosting), Apple Speech (`SpeechAnalyzer`), AVFoundation, IOKit power sources, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-19-accent-and-slang-design.md`. Executors read both.

## Global Constraints

- Work on branch `accent-and-slang`, created from `main` at `a871498` or later. Each task is done on its own branch from `accent-and-slang` in its own worktree, and merged back by the lead. Commit after each task. Do not push.
- macOS deployment target 26.0, Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY: complete`. No new package dependencies. FluidAudio stays at the revision pinned in `project.yml` unless a task proves a newer one is needed; say why in the commit.
- `project.yml` is the source of truth. Run `xcodegen generate` after adding or removing files, and commit the regenerated `Sotto.xcodeproj`.
- Do not change `CODE_SIGN_IDENTITY: "Apple Development"`, `DEVELOPMENT_TEAM: N7447R8KW2`, `CODE_SIGN_ENTITLEMENTS: App/Sotto.entitlements`, `ENABLE_HARDENED_RUNTIME: YES` or `ENABLE_DEBUG_DYLIB: NO`.
- Leave the hotkey path alone: `HotkeyMonitor`, `RightCommand`, `AppModel.watchHotkey`/`hotkeyTick`/`noteRightCommand`/`maintainTap`. Keep `AudioCapture` installing its tap with `inputNode.inputFormat(forBus: 0)`.
- `SottoCore` imports only Foundation. Stored data is plain JSON in `~/Library/Application Support/Sotto/`.
- New settings fields decode with defaults when missing; an unknown enum value keeps the default and every other field.
- Never launch a second Sotto while the owner's copy runs (both react to Right Command). Tests run through `xcodebuild test`, which doesn't launch the app.
- Never download models in tests. Engine code that downloads is exercised by the owner's manual checks.
- Build and test command (`$BUILD`): `xcodegen generate && xcodebuild -project Sotto.xcodeproj -scheme Sotto -destination 'platform=macOS' -derivedDataPath build/DerivedData build test 2>&1 | tail -5`. Passing means the output contains `** TEST SUCCEEDED **`. In a worktree, use that worktree's own `build/DerivedData`.
- Single test class: append `-only-testing:SottoCoreTests/<ClassName>` to the `xcodebuild` part.
- Commits use Conventional Commits with a lowercase imperative subject of at most 72 characters. No AI attribution or co-author trailers.
- Fixed values from the spec: clip retention 7 days; teacher idle threshold 5 minutes, mains power only; fix checks about 20 seconds after inserting and at the next dictation, within 2 minutes; a substitution is at most 4 words on each side; learned after 1 fix, 1 Compare pick, or the same teacher pair on 2 different clips; default typing model Parakeet v2; default teacher Cohere Transcribe (never auto-downloaded); Keep audio on by default; spelling Australian by default.

## Review Focus

Inputs the spec implies but doesn't spell out, most likely to bite first. Each has a pinning test in the task named.

- **An existing `settings.json` or `rulebook.json`** from before this project, including an explicit `"teacherModel": null`, keeps every value and decodes the new fields to their defaults (Off stays Off). Pinned in Task 1.
- **Code-looking words in prose** (backticks, camelCase, snake_case, `file.color`, URLs, paths, ALL-CAPS) are never respelled, while ordinary words in the same sentence are. Pinned in Task 2.
- **Very short takes and one-letter words** ("my G", "G") still produce a useful learned phrase with context, not a bare "G". Pinned in Task 4.
- **The owner deletes a learned word, then the teacher or a fix finds it again**: it stays deleted; adding it to Your words or picking it in Compare brings it back. Pinned in Task 4.
- **Clips at the retention boundary and clip records written by an older build** (missing optional fields) are handled without crashing or losing other clips. Pinned in Task 3.

## Execution waves

The lead runs tasks in waves. Tasks in the same wave touch different files and run in parallel, each in its own worktree. The lead merges each wave into `accent-and-slang`, regenerates the project, runs `$BUILD`, and resolves conflicts (usually `Sotto.xcodeproj/project.pbxproj`, which is regenerated rather than hand-merged).

| Wave | Tasks |
|---|---|
| 1 | Task 1 (catalog, settings, hint terms) |
| 2 | Task 2 (spelling), Task 3 (clips), Task 4 (learning logic), Task 5 (engine layer and Parakeet family) |
| 3 | Task 6 (hint words for Parakeet), Task 8 (Cohere engine), Task 9 (clip store and the commit pipeline) |
| 4 | Task 7 (Apple engine), Task 10 (fix watcher), Task 11 (teacher scheduler), Task 12 (Settings panes) |
| 5 | Task 13 (Compare window) |

---

### Task 1: Speech catalog, settings fields and hint terms

**Files:**
- Create: `Core/SpeechCatalog.swift`
- Modify: `Core/Settings.swift` (`AppSettings`)
- Test: `Tests/SpeechCatalogTests.swift`, `Tests/SettingsTests.swift`

**Interfaces:**
- Produces (all `public`, in `Core/SpeechCatalog.swift`):
  - `enum SpeechModelID: String, Codable, CaseIterable, Sendable { case parakeetV2, parakeetUltra, phonon2, parakeetV3, cohere, appleEnglish }`
  - `enum SpeechEngineKind: String, Sendable { case parakeet, cohere, apple }`
  - `struct SpeechModelInfo: Equatable, Sendable { let id: SpeechModelID; let name: String; let summary: String; let approximateMegabytes: Int?; let kind: SpeechEngineKind; let acceptsHints: Bool; let credit: String }`
  - `enum SpeechCatalog { static let all: [SpeechModelInfo]; static func info(_ id: SpeechModelID) -> SpeechModelInfo }` — `all` in the spec's table order: v2, Ultra, Phonon-2, v3, Cohere, Apple.
  - `enum SpellingVariety: String, Codable, CaseIterable, Sendable { case australian, british, american; var localeIdentifier: String; var label: String }` — locales `en_AU`, `en_GB`, `en_US`; labels "Australian", "British", "American".
  - `struct HintTerm: Codable, Equatable, Sendable { var text: String; var aliases: [String] }`
  - `AppSettings` gains `typingModel: SpeechModelID = .parakeetV2`, `teacherModel: SpeechModelID? = .cohere` (nil means Off), `spelling: SpellingVariety = .australian`, `keepAudio: Bool = true`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SpeechCatalogTests.swift
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

// Tests/SettingsTests.swift
func testOldSettingsDecodeNewFieldsToDefaults() throws {
    let json = #"{"keepFirstSyllable":false,"historyHours":24,"dictationCount":7}"#
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    XCTAssertEqual(s.historyHours, 24); XCTAssertFalse(s.keepFirstSyllable); XCTAssertEqual(s.dictationCount, 7)
    XCTAssertEqual(s.typingModel, .parakeetV2); XCTAssertEqual(s.teacherModel, .cohere)
    XCTAssertEqual(s.spelling, .australian); XCTAssertTrue(s.keepAudio)
}
func testExplicitNullTeacherStaysOff() throws {
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"teacherModel":null}"#.utf8))
    XCTAssertNil(s.teacherModel)
}
func testUnknownModelKeepsDefaultAndOtherFields() throws {
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"typingModel":"whisper","spelling":"british","historyHours":24}"#.utf8))
    XCTAssertEqual(s.typingModel, .parakeetV2); XCTAssertEqual(s.spelling, .british); XCTAssertEqual(s.historyHours, 24)
}
func testSettingsRoundTripKeepsTeacherOff() throws {
    var s = AppSettings(); s.teacherModel = nil
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    XCTAssertNil(back.teacherModel)
}
```

- [ ] **Step 2: Run them and see them fail** — `$BUILD` fails to compile (types missing).

- [ ] **Step 3: Implement `Core/SpeechCatalog.swift` and the `AppSettings` fields**

Decode `teacherModel` with `container.contains(.teacherModel)`: when the key is present, `try? decodeIfPresent` (null → nil = Off; unknown string → default `.cohere`); when absent, the default. Encode nil explicitly (`encode(_:forKey:)` of an Optional writes null) so Off survives a round trip; write a custom `encode(to:)` if synthesized encoding omits nil.

Credits: Parakeet v2 is "NVIDIA Parakeet TDT 0.6B v2 (CC-BY-4.0), via FluidAudio." For Ultra, Phonon-2, v3 and Cohere Transcribe, read each Hugging Face model card (repos listed in FluidAudio's `Documentation/Models.md`, "Model Sources"; the Hugging Face MCP tools or the web can read them) and write the licence into `credit`. If a licence forbids use in a free app, remove that model from `SpeechModelID` and the catalog, and report it. Summaries and sizes come from the spec's model table.

- [ ] **Step 4: `$BUILD` passes.**

- [ ] **Step 5: Commit** — `feat(core): add speech model catalog and new settings fields`

### Task 2: Spelling conversion

**Files:**
- Create: `Core/SpellingConverter.swift`, `Core/SpellingTable.swift` (generated word pairs)
- Test: `Tests/SpellingConverterTests.swift`

**Interfaces:**
- Consumes: `SpellingVariety` (Task 1).
- Produces: `public enum SpellingConverter { public static func convert(_ text: String, to variety: SpellingVariety) -> String; public static let credit: String? }`

- [ ] **Step 1: Write the failing tests**

```swift
func testAustralianRespellsOrdinaryWords() {
    XCTAssertEqual(SpellingConverter.convert("make the button color darker", to: .australian), "make the button colour darker")
    XCTAssertEqual(SpellingConverter.convert("I realize the center is gray", to: .british), "I realise the centre is grey")
}
func testCaseIsPreserved() {
    XCTAssertEqual(SpellingConverter.convert("Color me surprised", to: .australian), "Colour me surprised")
}
func testCodeLookingWordsAreSkipped() {
    let text = "use `color` and fooColor and font_color and file.color, see https://example.com/color or ./color/x"
    XCTAssertEqual(SpellingConverter.convert(text, to: .australian), text)
    XCTAssertEqual(SpellingConverter.convert("set COLOR now", to: .australian), "set COLOR now")
}
func testAmericanGoesTheOtherWay() {
    XCTAssertEqual(SpellingConverter.convert("the colour of the centre", to: .american), "the color of the center")
}
func testAustralianKeepsProgram() {
    XCTAssertEqual(SpellingConverter.convert("a TV program", to: .australian), "a TV program")
    XCTAssertEqual(SpellingConverter.convert("a TV program", to: .british), "a TV programme")
}
func testSwearingIsUntouched() {
    XCTAssertEqual(SpellingConverter.convert("fucking shit, the color", to: .australian), "fucking shit, the colour")
    XCTAssertEqual(TranscriptFormatter.format("fuck this shit", mode: .prose), "Fuck this shit.")
    XCTAssertEqual(Rulebook().remember(heard: "john", written: "Jon").applying(to: "fuck off john"), "fuck off Jon")
}
func testPunctuationAroundWordsSurvives() {
    XCTAssertEqual(SpellingConverter.convert("Color, flavor; honor!", to: .australian), "Colour, flavour; honour!")
}
```

- [ ] **Step 2: Run `-only-testing:SottoCoreTests/SpellingConverterTests`; expect a compile failure.**

- [ ] **Step 3: Implement**

`SpellingTable.swift` holds US→UK word pairs as a Swift dictionary literal generated from a list whose licence allows redistribution in a free app (VarCon, by Kevin Atkinson, is the suggested source; confirm its licence text). Put the source, licence and generation command in a header comment, and set `credit` accordingly (nil if no credit is required). Australian is British minus the exceptions set (at least `program`). American inverts the table. A word is code-looking, and skipped, when it is inside a backtick span, contains `_`, `/`, `\`, `://`, or a `.` between letters, has an uppercase letter after a lowercase one, or is all caps and longer than one letter. Respell only whole words; keep surrounding punctuation; match case as lower, Capitalised or unchanged.

- [ ] **Step 4: `$BUILD` passes.**

- [ ] **Step 5: Commit** — `feat(core): add australian, british and american spelling`

### Task 3: Clip records, retention and Compare scoring

**Files:**
- Create: `Core/ClipRecord.swift`
- Test: `Tests/ClipRecordTests.swift`

**Interfaces:**
- Consumes: `SpeechModelID` (Task 1).
- Produces (public):
  - `struct ClipRecord: Codable, Equatable, Sendable, Identifiable { var id: UUID; var date: Date; var bundleID: String?; var domain: String?; var durationSeconds: Double; var typingModel: SpeechModelID; var rawText: String; var hintedText: String; var typedText: String; var teacherModel: SpeechModelID?; var teacherText: String?; var modelTexts: [String: String]; var pickedModel: SpeechModelID?; var correctedText: String? }` — `modelTexts` is keyed by `SpeechModelID.rawValue` so the JSON stays a plain object. Missing optional fields and a missing `modelTexts` decode to nil / `[:]`.
  - `enum ClipRetention { static let days = 7; static func expired(_ records: [ClipRecord], now: Date) -> [ClipRecord] }` — a record is expired when `now.timeIntervalSince(date) >= 7 * 86_400`.
  - `struct ModelScore: Equatable, Sendable { var right: Int; var judged: Int }` and `enum CompareScore { static func tally(_ records: [ClipRecord]) -> [SpeechModelID: ModelScore] }` — a clip is judged when it has `pickedModel` or `correctedText`. For each model with a text on a judged clip, it's right when it's the picked model, or its text equals `correctedText` after lowercasing and removing punctuation.

- [ ] **Step 1: Write the failing tests**

```swift
func testRetentionBoundary() {
    let now = Date(timeIntervalSince1970: 10_000_000)
    let fresh = record(date: now.addingTimeInterval(-7 * 86_400 + 1))
    let old = record(date: now.addingTimeInterval(-7 * 86_400))
    XCTAssertEqual(ClipRetention.expired([fresh, old], now: now).map(\.id), [old.id])
}
func testOldRecordWithoutOptionalFieldsDecodes() throws {
    let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":0,"durationSeconds":1.5,"typingModel":"parakeetV2","rawText":"hi","hintedText":"hi","typedText":"Hi."}"#
    let r = try JSONDecoder().decode(ClipRecord.self, from: Data(json.utf8))
    XCTAssertEqual(r.modelTexts, [:]); XCTAssertNil(r.pickedModel); XCTAssertNil(r.teacherText)
}
func testTallyCountsPicksAndCorrections() {
    var a = record(); a.modelTexts = ["parakeetV2": "What's up, Madgie?", "parakeetUltra": "What's up, my G?"]; a.pickedModel = .parakeetUltra
    var b = record(); b.modelTexts = ["parakeetV2": "My gee.", "parakeetUltra": "my G"]; b.correctedText = "My G."
    var c = record(); c.modelTexts = ["parakeetV2": "unjudged"]
    let score = CompareScore.tally([a, b, c])
    XCTAssertEqual(score[.parakeetUltra], ModelScore(right: 2, judged: 2))
    XCTAssertEqual(score[.parakeetV2], ModelScore(right: 0, judged: 2))
}
```

(`record(date:)` is a test helper that fills required fields.)

- [ ] **Step 2: Run `-only-testing:SottoCoreTests/ClipRecordTests`; expect a compile failure.**
- [ ] **Step 3: Implement `Core/ClipRecord.swift`** with a custom `init(from:)` for the defaults above.
- [ ] **Step 4: `$BUILD` passes.**
- [ ] **Step 5: Commit** — `feat(core): add clip records, retention and compare scoring`

### Task 4: Phrase alignment, sound-alike matching, fix detection and the lexicon

**Files:**
- Create: `Core/PhraseAligner.swift`, `Core/SoundAlike.swift`, `Core/FixDetector.swift`, `Core/Lexicon.swift`
- Test: `Tests/LearningTests.swift`

**Interfaces:**
- Consumes: `HintTerm` (Task 1).
- Produces (public):
  - `struct Substitution: Codable, Equatable, Hashable, Sendable { var heard: String; var written: String }` — `heard` is lowercased and punctuation-free; `written` keeps the reference's case for the substituted words and lowercases added context words unless they are "I" or all caps.
  - `enum PhraseAligner { static func substitutions(from hypothesis: String, to reference: String, maxWords: Int = 4, normalize: (String) -> String = { $0 }) -> [Substitution] }` — word-level alignment (Levenshtein over words). Words are compared after lowercasing and stripping punctuation, and then `normalize` is applied to each word separately. Each maximal run of differing words with both sides non-empty and each side ≤ `maxWords` words is a substitution. When the written side is one word shorter than 3 characters, extend both sides by the preceding word (or the following word at the start).
  - `enum SoundAlike { static func similar(_ a: String, _ b: String) -> Bool }` — phonetic-key comparison (the algorithm is the implementer's choice) satisfying the tests.
  - `enum FixDetector { static func fix(inserted: String, fieldText: String, near offset: Int? = nil) -> Substitution? }` (as built: `near` windows the field ±300 UTF-16 units; without it, half the typed words must anchor) — locates the inserted text in the field by word alignment; returns the single changed span when the rest is intact, the span is ≤4 words on each side, not a pure deletion, and `SoundAlike.similar(heard, written)`; otherwise nil.
  - `enum LearnSource: String, Codable, Sendable { case fix, compare, teacher }`
  - `struct LearnedWord: Codable, Equatable, Sendable, Identifiable { var id: UUID; var written: String; var heardForms: [String]; var sources: [LearnSource]; var count: Int; var teacherClips: [UUID]; var teacherClipsByHeard: [String: [UUID]]; var learned: Bool }` (as built: teacher clips are counted per heard form)
  - `struct Lexicon: Codable, Equatable, Sendable` with `var entries: [LearnedWord]`, `var yourWords: [String]`, `var blocked: [String]`, and:
    - `func recording(_ s: Substitution, source: LearnSource, clipID: UUID?) -> Lexicon`
    - `var learnedWords: [LearnedWord]`
    - `func deleting(id: UUID) -> Lexicon` (removes it and blocks its normalised written form)
    - `func addingYourWord(_ word: String) -> Lexicon` (also unblocks it)
    - `func removingYourWord(_ word: String) -> Lexicon`
    - `var hintTerms: [HintTerm]` (learned words with their heard forms as aliases, then your words with no aliases; no duplicates by normalised text)
  - Rules: `.fix` and `.compare` learn at once; `.teacher` learns when the same pair has been seen on 2 different clip IDs. A blocked written form ignores `.fix` and `.teacher`; `.compare` unblocks it and learns. Entries match on normalised `written` (lowercased, single-spaced); new heard forms are added to that entry.

- [ ] **Step 1: Write the failing tests**

```swift
func testAlignerFindsTheMishearing() {
    XCTAssertEqual(PhraseAligner.substitutions(from: "What's up, Madgie?", to: "What's up, my G?"),
                   [Substitution(heard: "madgie", written: "my G")])
}
func testShortWrittenWordGetsContext() {
    XCTAssertEqual(PhraseAligner.substitutions(from: "My gee.", to: "My G."), [Substitution(heard: "my gee", written: "my G")])
}
func testAlignerIgnoresCasePunctuationAndNormalisedSpelling() {
    XCTAssertEqual(PhraseAligner.substitutions(from: "the colour", to: "The color.", normalize: { $0 == "colour" ? "color" : $0 }), [])
}
func testLongRewritesAndPureInsertionsAreIgnored() {
    XCTAssertEqual(PhraseAligner.substitutions(from: "a b c d e f g", to: "one two three four five six seven"), [])
    XCTAssertEqual(PhraseAligner.substitutions(from: "send it", to: "send it now"), [])
}
func testSoundAlike() {
    XCTAssertTrue(SoundAlike.similar("margie", "my g")); XCTAssertTrue(SoundAlike.similar("madgie", "my g"))
    XCTAssertTrue(SoundAlike.similar("gee", "g"))
    XCTAssertFalse(SoundAlike.similar("great", "awesome")); XCTAssertFalse(SoundAlike.similar("tuesday", "wednesday"))
}
func testFixDetector() {
    XCTAssertEqual(FixDetector.fix(inserted: " What's up, Margie?", fieldText: "hey mate. What's up, my G? see ya"),
                   Substitution(heard: "margie", written: "my G"))
    XCTAssertNil(FixDetector.fix(inserted: "That was great.", fieldText: "That was awesome."))
    XCTAssertNil(FixDetector.fix(inserted: "What's up, Margie?", fieldText: "What's up, Margie?"))
    XCTAssertNil(FixDetector.fix(inserted: "send it to Margie now", fieldText: ""))
    XCTAssertNil(FixDetector.fix(inserted: "call Margie and Madgie", fieldText: "call my G and my G"))
}
func testLexiconThresholdsAndBlocking() {
    let pair = Substitution(heard: "madgie", written: "my G")
    var lex = Lexicon()
    let clip1 = UUID(), clip2 = UUID()
    lex = lex.recording(pair, source: .teacher, clipID: clip1)
    XCTAssertTrue(lex.learnedWords.isEmpty)
    lex = lex.recording(pair, source: .teacher, clipID: clip1)
    XCTAssertTrue(lex.learnedWords.isEmpty)                      // same clip twice doesn't count
    lex = lex.recording(pair, source: .teacher, clipID: clip2)
    XCTAssertEqual(lex.learnedWords.map(\.written), ["my G"])
    XCTAssertEqual(lex.hintTerms, [HintTerm(text: "my G", aliases: ["madgie"])])
    lex = lex.deleting(id: lex.learnedWords[0].id)
    lex = lex.recording(Substitution(heard: "margie", written: "my G"), source: .fix, clipID: nil)
    XCTAssertTrue(lex.learnedWords.isEmpty)                      // blocked
    lex = lex.recording(pair, source: .compare, clipID: nil)
    XCTAssertEqual(lex.learnedWords.map(\.written), ["my G"])  // compare unblocks
}
func testFixLearnsAtOnceAndYourWordsUnblock() {
    var lex = Lexicon().recording(Substitution(heard: "margie", written: "my G"), source: .fix, clipID: nil)
    XCTAssertEqual(lex.learnedWords.count, 1)
    lex = lex.deleting(id: lex.learnedWords[0].id).addingYourWord("my G")
    XCTAssertTrue(lex.blocked.isEmpty)
    XCTAssertEqual(lex.hintTerms.map(\.text), ["my G"])
}
```

- [ ] **Step 2: Run `-only-testing:SottoCoreTests/LearningTests`; expect a compile failure.**
- [ ] **Step 3: Implement the four files to the interfaces above.**
- [ ] **Step 4: `$BUILD` passes.**
- [ ] **Step 5: Commit** — `feat(core): add phrase alignment, fix detection and lexicon`

### Task 5: Engine layer and the Parakeet family

**Files:**
- Create: `App/Speech/SpeechEngine.swift`, `App/Speech/ParakeetFamilyEngine.swift`, `App/Speech/EngineFactory.swift`, `App/Speech/ModelLibrary.swift`
- Delete: `App/ParakeetEngine.swift` (move `ModelPhase` into `App/Speech/SpeechEngine.swift` unchanged)
- Modify: `App/AppModel.swift` (replace `engine` with `library`; `bootstrap`, `retryModel`, `commit`'s transcription call)

**Interfaces:**
- Consumes: `SpeechModelID`, `SpeechCatalog`, `HintTerm`, `AppSettings.typingModel` (Task 1).
- Produces:
  - `enum ModelState: Equatable, Sendable { case notDownloaded, downloading(Double?), preparing, ready, failed(String) }`
  - `struct EngineResult: Equatable, Sendable { var raw: String; var hinted: String }` (Task 6 makes `hinted` differ)
  - `protocol SpeechEngine: Actor { nonisolated var id: SpeechModelID { get }; func isDownloaded() -> Bool; func prepare(progress: @escaping @Sendable (Double?) -> Void) async throws; var isLoaded: Bool { get }; func transcribe(_ samples: [Float], hints: [HintTerm]) async throws -> EngineResult?; func unload(); func deleteFiles() throws }`
  - `func makeEngine(for id: SpeechModelID, spelling: SpellingVariety) -> (any SpeechEngine)?` in `EngineFactory.swift`: returns `ParakeetFamilyEngine` for the four Parakeet ids, nil for `.cohere` and `.appleEnglish` (Tasks 7 and 8 each change one line).
  - `@MainActor @Observable final class ModelLibrary` with `private(set) var states: [SpeechModelID: ModelState]`, `private(set) var typingModel: SpeechModelID`, `init(typingModel: SpeechModelID, spelling: SpellingVariety)`, `func setSpelling(_ variety: SpellingVariety)` (rebuilds the Apple engine, if any, for the new locale), `func refreshDownloadStates()`, `func prepareTypingModel() async`, `func select(_ id: SpeechModelID) async`, `func download(_ id: SpeechModelID) async`, `func delete(_ id: SpeechModelID) async throws`, `func transcribeTyping(_ samples: [Float], hints: [HintTerm]) async -> EngineResult?`, `func withLoaded<T: Sendable>(_ id: SpeechModelID, _ body: @Sendable (any SpeechEngine) async throws -> T) async throws -> T` (loads the model if it isn't the typing model, runs `body`, then unloads it), and `var typingPhase: ModelPhase` (maps the typing model's state for existing callers).

FluidAudio facts for this task (pinned revision):
- One call loads every Parakeet version: `AsrModels.downloadAndLoad(to: nil, configuration: nil, version: <.v2|.v3|.ultra|.phonon2>, progressHandler:)`. The handler is `@Sendable (DownloadProgress) -> Void` on an arbitrary queue; `DownloadProgress.fractionCompleted` and `.phase` (`.listing`, `.downloading`, `.compiling`). Map `.compiling` to `ModelState.preparing`.
- Then `AsrManager()` + `loadModels(_:)`, and `transcribe(_:decoderState:)` with `TdtDecoderState.make(decoderLayers: manager.decoderLayerCount)`, exactly as `ParakeetEngine` does today. Two decoder layers for all four versions.
- Downloaded check: `AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version), version: version)`. Delete: `FileManager.default.removeItem(at: AsrModels.defaultCacheDirectory(for: version))`.
- Phonon-2's first load compiles for about 3 minutes; Ultra prefers the Neural Engine. Keep default compute units.

- [ ] **Step 1: Replace `ParakeetEngine` with `ParakeetFamilyEngine` for `.parakeetV2` and wire `ModelLibrary` into `AppModel`**, with no behaviour change: v2 downloads and loads at launch, `modelStatusLine` and Retry still work, and `commit` calls `library.transcribeTyping(samples, hints: [])` and uses `.hinted`.
- [ ] **Step 2: `$BUILD` passes.** Existing tests cover nothing here; the build is the check.
- [ ] **Step 3: Add the other three versions and `select`.** `select` sets state `.preparing` for the new model, keeps transcribing with the previous engine until the new one is ready, then switches and unloads the old one. If preparing fails, stay on the previous model and set `.failed(reason)` on the new one. `delete` throws for the typing model. Only the typing model stays loaded.
- [ ] **Step 4: `$BUILD` passes.**
- [ ] **Step 5: Commit** — `feat(speech): add engine layer and parakeet model family`

### Task 6: Hint words for Parakeet models

**Files:**
- Create: `App/Speech/HintBooster.swift`
- Modify: `App/Speech/ParakeetFamilyEngine.swift` (`transcribe`)

**Interfaces:**
- Consumes: `SpeechEngine`, `EngineResult` (Task 5), `HintTerm` (Task 1).
- Produces: `actor HintBooster { func apply(text: String, tokenTimings: [TokenTiming], samples: [Float], hints: [HintTerm]) async -> String }` — returns the rescored text, or `text` unchanged.

FluidAudio facts:
- CTC model: `CtcModels.downloadAndLoad(to: nil, variant: .ctc110m)` (about 97.5 MB, no progress handler). Download it the first time `hints` is non-empty; until it's ready, return `text` unchanged.
- Vocabulary: `CustomVocabularyTerm(text: hint.text, aliases: hint.aliases)` in `CustomVocabularyContext(terms:)`; session `try await VocabularyBoostingSession(vocabulary:ctcModels:)`. Rebuild the session only when the hint list changes.
- Preflight `session.hasCTCRescoringCandidates(text:tokenTimings:)` (synchronous, no inference). Only when it returns true, call `await session.rescore(text:tokenTimings:audioSamples:)`; use `output.text` when `output.wasModified`.
- `ASRResult.tokenTimings` supplies the timings, starting at the first sample. The CTC tokenizer is independent of the primary model, so all four Parakeet versions work. Avoid the stale doc example that calls `AsrManager.transcribe(_:customVocabulary:)`, which doesn't exist.

- [ ] **Step 1: Implement `HintBooster` and call it from `ParakeetFamilyEngine.transcribe`**: `raw` is the model's text, `hinted` is the booster's output.
- [ ] **Step 2: `$BUILD` passes.**
- [ ] **Step 3: Measure.** In a debug log line (subsystem `app.sotto.desktop`, category `dictation`), record milliseconds spent in the booster per take. With no hint words, it must be 0 work: no CTC load and no preflight.
- [ ] **Step 4: Commit** — `feat(speech): boost hint words for parakeet models`

### Task 7: Apple engine, locale and contextual strings

**Files:**
- Create: `App/Speech/AppleEngine.swift`
- Modify: `App/LiveLine.swift` (locale and context), `App/Speech/EngineFactory.swift` (one line), `App/AppModel.swift` (add `refreshLiveContext()`, which calls `live.configure(locale: settings.spelling, hints: lexicon.hintTerms)`; call it at launch and from `setSpelling`, `addYourWord`, `removeYourWord`, `deleteLearnedWord` and `recordLearning`, which Task 9 added)

**Interfaces:**
- Consumes: `SpeechEngine` (Task 5), `SpellingVariety` and `HintTerm` (Task 1).
- Produces:
  - `actor AppleEngine: SpeechEngine` for `.appleEnglish`: `isDownloaded()` is true when the locale's asset is installed; `prepare` installs it through `AssetInventory`; `transcribe` runs a one-off `SpeechAnalyzer` over the given 16 kHz samples (for Compare and the teacher) and returns `EngineResult(raw:hinted:)` with both equal. `deleteFiles()` is a no-op.
  - `LiveLine.configure(locale: SpellingVariety, hints: [HintTerm])`, called at launch and when spelling or hints change; it takes effect from the next take.
  - `AppleEngine.init(locale: SpellingVariety)`; `ModelLibrary` passes the current spelling.

Apple Speech facts (SDK 27; all available on macOS 26):
- `SpeechTranscriber.supportedLocale(equivalentTo:)` maps `Locale(identifier: variety.localeIdentifier)`; `en_AU`, `en_GB` and `en_US` are all supported and installed on the owner's Mac.
- `AnalysisContext()` with `context.contextualStrings[.general] = hints.map(\.text)`; attach with `try await analyzer.setContext(context)` after `SpeechAnalyzer(modules:options:)`.
- Whether `SpeechTranscriber` honours contextual strings is undocumented. `DictationTranscriber(locale:preset:)` (presets include `.progressiveShortDictation`, `.shortDictation`) is the alternative.
- Neither transcriber masks swearing unless `.etiquetteReplacements` is passed. Never pass it.

- [ ] **Step 1: Implement `LiveLine.configure` and the locale switch** (replace the hard-coded `en-US`).
- [ ] **Step 2: Implement `AppleEngine`** and return it from `makeEngine(for: .appleEnglish, spelling:)`.
- [ ] **Step 3: Check contextual strings.** Add a DEBUG-only check, run by hand through a scratch command-line target or a Swift script outside the repo (not in the app): transcribe a short synthesized or recorded sample containing an unusual word, with and without the word as a contextual string, using `SpeechTranscriber` and then `DictationTranscriber`. If only `DictationTranscriber` changes the result, use it for both `LiveLine` and `AppleEngine`, keeping progressive results for live captions. Record the finding in the commit body.
- [ ] **Step 4: `$BUILD` passes.**
- [ ] **Step 5: Commit** — `feat(speech): add apple engine with spelling locale and hints`

### Task 8: Cohere Transcribe engine

**Files:**
- Create: `App/Speech/CohereEngine.swift`
- Modify: `App/Speech/EngineFactory.swift` (one line)

**Interfaces:**
- Consumes: `SpeechEngine`, `EngineResult` (Task 5).
- Produces: `actor CohereEngine: SpeechEngine` for `.cohere`. Hints are ignored; `raw == hinted`.

FluidAudio facts:
- Download with `ModelHub.download(.cohereTranscribeCoreml, to: MLModelConfigurationUtils.defaultModelsDirectory(), progressHandler:)`. Files land in `<dir>/cohere-transcribe/q8`; the downloaded check is that folder containing `cohere_encoder.mlmodelc`, `cohere_decoder_cache_external_v3.mlmodelc` and `vocab.json`. Delete removes `<dir>/cohere-transcribe`.
- Load with `CoherePipeline.loadModels(encoderDir: q8, decoderDir: q8, vocabDir: q8)` → `LoadedModels`; transcribe with `CoherePipeline().transcribeLong(audio:models:language: .english)` and read `.text`. `transcribeLong` handles any length.
- There's no unload API: drop the `LoadedModels` and pipeline references. The first load in each process compiles for about 3 minutes, so `prepare` reports `.preparing` for that time.

- [ ] **Step 1: Implement `CohereEngine`** and return it from `makeEngine(for: .cohere, spelling:)`.
- [ ] **Step 2: `$BUILD` passes.**
- [ ] **Step 3: Commit** — `feat(speech): add cohere transcribe engine`

### Task 9: Clip store and the commit pipeline

**Files:**
- Create: `App/ClipStore.swift`
- Modify: `App/Stores.swift` (lexicon), `App/AppModel.swift` (`commit`, settings actions), `App/Settings/SettingsPanes.swift` (`PrivacySettingsPane` statement only)

**Interfaces:**
- Consumes: `ClipRecord`, `ClipRetention` (Task 3), `SpellingConverter` (Task 2), `Lexicon` (Task 4), `ModelLibrary` (Task 5), `AppSettings` fields (Task 1).
- Produces:
  - `@MainActor final class ClipStore { init(directory: URL); private(set) var records: [ClipRecord]; func save(samples: [Float], record: ClipRecord); func samples(for id: UUID) -> [Float]?; func update(_ record: ClipRecord); func prune(now: Date); func deleteAll() }`. Each clip is `<id>.f32` (little-endian Float32 samples) plus `<id>.json` in `~/Library/Application Support/Sotto/Clips/`. Unreadable files are skipped, not fatal.
  - `LocalStore.loadLexicon() -> Lexicon` and `LocalStore.save(lexicon:)` (`lexicon.json`).
  - On `AppModel`: `var lexicon: Lexicon`, `let clips: ClipStore`, `func setKeepAudio(_ on: Bool, deleteExisting: Bool)`, `func deleteAllClips()`, `func setSpelling(_ variety: SpellingVariety)`, `func setTypingModel(_ id: SpeechModelID)`, `func setTeacherModel(_ id: SpeechModelID?)`, `func addYourWord(_ word: String)`, `func removeYourWord(_ word: String)`, `func deleteLearnedWord(id: UUID)`, `func recordLearning(_ s: Substitution, source: LearnSource, clipID: UUID?)`.

The commit pipeline, in order:
1. If `library.typingModel == .appleEnglish`, `raw = hinted =` the live session's final text. Otherwise `library.transcribeTyping(samples, hints: lexicon.hintTerms)`; if it returns nil, fall back to the live text as today.
2. `formatted = TranscriptFormatter.format(hinted, mode:)`.
3. In Prose only: `SpellingConverter.convert(formatted, to: settings.spelling)`.
4. `rulebook.applying(to:)` (the owner's Names win over spelling).
5. `InsertJoin.fit` and insert, as today.
6. When `settings.keepAudio`, the take wasn't cancelled and the text was non-empty, save a `ClipRecord` with `rawText: raw`, `hintedText: hinted`, `typedText` (step 4's result), `typingModel`, `bundleID`, `domain` and duration. Then `clips.prune(now:)`. Also prune at launch.

Privacy statement, exact copy:
- Keep audio on: "Audio of each dictation is kept on this Mac for 7 days to improve recognition, and is never sent anywhere. Nothing leaves this Mac except model downloads."
- Keep audio off: "Audio is never saved, and nothing leaves this Mac except model downloads."

- [ ] **Step 1: Implement `ClipStore` and the lexicon store.**
- [ ] **Step 2: Rework `commit`** as above, and add the settings actions. `setSpelling` also calls `library.setSpelling` (Task 7, in the next wave, adds the live-caption refresh); `addYourWord`, `removeYourWord`, `deleteLearnedWord` and `recordLearning` save the lexicon.
- [ ] **Step 3: Update the Privacy statement.**
- [ ] **Step 4: `$BUILD` passes.**
- [ ] **Step 5: Commit** — `feat(dictation): keep clips, apply spelling and pass hint words`

### Task 10: Fix watcher

**Files:**
- Create: `App/FixWatcher.swift`
- Modify: `App/TextInserter.swift` (expose the last insertion and a field-text read), `App/AppModel.swift` (`beginTake` calls `fixWatcher.check()`; after a successful insert, `fixWatcher.watch(...)`)

**Interfaces:**
- Consumes: `FixDetector`, `Substitution` (Task 4), `AppModel.recordLearning` (Task 9).
- Produces:
  - `TextInserter.fieldText(of element: AXUIElement) -> String?`: `kAXValueAttribute` as a String, nil for secure fields, or when the value is longer than 100,000 characters.
  - `TextInserter.lastInsertion: (element: AXUIElement, text: String, offset: Int?, date: Date)?`, set after each successful insert (the existing `recent` record can become this). `offset` is the UTF-16 cursor location read just before inserting (the selected-range location `axTextBeforeCursor` already reads), or nil when the field didn't report it.
  - `@MainActor final class FixWatcher { init(inserter: TextInserter, onFix: @escaping (Substitution) -> Void); func watch(); func check() }`.

Behaviour: `watch()` schedules a check about 20 seconds after an insertion. `check()` runs at most once per insertion, only within 2 minutes of it. It reads `fieldText(of:)` for the remembered element and calls `FixDetector.fix(inserted:fieldText:near:)` with the remembered offset; a non-nil result goes to `onFix`, which `AppModel` wires to `recordLearning(_, source: .fix, clipID: nil)`. A newer insertion replaces the pending one. Elements that no longer exist, or that return nil, are dropped silently.

- [ ] **Step 1: Implement and wire as above.**
- [ ] **Step 2: `$BUILD` passes.**
- [ ] **Step 3: Commit** — `feat(learning): learn from fixes made right after typing`

### Task 11: Teacher scheduler

**Files:**
- Create: `App/TeacherScheduler.swift`
- Modify: `App/AppModel.swift` (create it, call `noteDictation()` from `beginTake`)

**Interfaces:**
- Consumes: `ModelLibrary.withLoaded` (Task 5), `ClipStore` (Task 9), `PhraseAligner` and `Lexicon` (Task 4), `SpellingConverter` (Task 2), `AppSettings.teacherModel`.
- Produces: `@MainActor final class TeacherScheduler { init(library: ModelLibrary, clips: ClipStore, settings: () -> AppSettings, onSubstitution: @escaping (Substitution, UUID) -> Void); func start(); func noteDictation() }`.

Behaviour:
- A timer every 60 seconds checks all of these: a teacher is set and downloaded; no dictation for 5 minutes; the Mac is on mains power (`IOPSCopyPowerSourcesInfo` + `IOPSGetProvidingPowerSourceType` equal to `kIOPMACPowerKey`); and some clips have no `teacherText` and weren't typed by the teacher model.
- When all hold, it runs `library.withLoaded(teacher)` over those clips, oldest first. For each clip, it saves `teacherModel` and `teacherText` on the record, then calls `PhraseAligner.substitutions(from: record.rawText, to: teacherText, normalize: { SpellingConverter.convert($0, to: .american) })` and passes each result to `onSubstitution` with the clip's ID. `AppModel` wires this to `recordLearning(_, source: .teacher, clipID:)`.
- `noteDictation()` and unplugging (checked between clips) stop the run after the current clip, and the model is unloaded.

- [ ] **Step 1: Implement and wire as above.**
- [ ] **Step 2: `$BUILD` passes.**
- [ ] **Step 3: Commit** — `feat(learning): add background teacher model`

### Task 12: Speech, Dictionary and About panes

**Files:**
- Modify: `App/Settings/SettingsPanes.swift` (`SpeechSettingsPane`, `DictionarySettingsPane`, `AboutSettingsPane`)

**Interfaces:**
- Consumes: `ModelLibrary` states and actions (Task 5), `AppModel` actions (Task 9), `Lexicon` (Task 4), `SpeechCatalog` and `SpellingConverter.credit` (Tasks 1 and 2).

What each pane shows (copy is the builder's, within the spec):
- **Speech:**
  - Mode, unchanged.
  - **Typing model**: one row per catalog entry, with a radio button, name, summary and size. On the right: "In use", "Preparing…", a progress bar, Download, or a Delete control for downloaded models other than the one in use. Selecting a model calls `setTypingModel`. A model that doesn't accept hints says "No hint words".
  - **Teacher**: a picker with Off and every model except the typing model. When the chosen teacher isn't downloaded, a row reads "Download Cohere Transcribe (1.8 GB) to start background learning" (or the chosen model's name and size) with a Download button.
  - **Spelling**: Australian, British or American.
  - **Compare models**: the Keep audio toggle (turning it off asks "Delete the N kept clips?" with Delete and Keep), the clip count, and Delete all with a confirmation. The Compare… button arrives with Task 13.
- **Dictionary:** three sections.
  - Learned: the written form, its misheard forms, where it came from and the count, with Delete.
  - Your words: a list with Delete, and a field plus Add.
  - Names: unchanged.
- **About:** the version, then each catalog model's `credit`, and `SpellingConverter.credit` when it's non-nil.

- [ ] **Step 1: Implement the three panes.**
- [ ] **Step 2: `$BUILD` passes.**
- [ ] **Step 3: Commit** — `feat(settings): add model, teacher, spelling and learned words`

### Task 13: Compare window (wave 5, after Task 12 merges)

**Files:**
- Create: `App/Compare/CompareWindowController.swift`, `App/Compare/CompareView.swift`, `App/Compare/CompareRunner.swift`
- Modify: `App/AppModel.swift` (`openCompare()`), `App/Settings/SettingsPanes.swift` (the Compare… button in the Compare models section)

**Interfaces:**
- Consumes: `ClipStore`, `ClipRecord`, `CompareScore` (Tasks 3 and 9), `ModelLibrary.withLoaded` (Task 5), `AppModel.recordLearning` and `lexicon.hintTerms` (Task 9), `PhraseAligner` (Task 4).
- Produces: `AppModel.openCompare()`; `@MainActor final class CompareRunner { func start(); func stop() }`.

Behaviour:
- The window lists clips newest first. Each shows a play button (AVAudioPlayer over the clip's samples), the time, the app name and the length.
- Under each clip, every downloaded model's text appears, from `record.modelTexts`, falling back to `rawText` for the typing model.
- `CompareRunner` runs while the window is open: one model at a time through `withLoaded`, with hint words, over clips missing that model's text. It saves each result into `modelTexts`, shows overall progress, and stops on close or when a dictation starts.
- Clicking a model's text sets `pickedModel`. "None of these" opens a field for `correctedText`.
- Each pick or correction calls `recordLearning` with `.compare` for each substitution from `PhraseAligner.substitutions(from: record.rawText, to: chosenText)`.
- The header shows `CompareScore.tally` for each model as "right / judged".

- [ ] **Step 1: Implement the window, runner and button.**
- [ ] **Step 2: `$BUILD` passes.**
- [ ] **Step 3: Commit** — `feat(compare): add compare window with model scoring`

## Manual checklist for the owner

These need a real microphone or screen:
- [ ] Download, switch to and delete each model; dictate with each into T3 Code and Discord.
- [ ] Parakeet v2 types as fast as before.
- [ ] Clips appear, play in Compare, and go after Delete all. Turning Keep audio off stops new clips.
- [ ] Compare runs every downloaded model and keeps score.
- [ ] Fix a misheard word right after Sotto types it; it shows under Learned, and the next take gets it right.
- [ ] Delete a learned word; it doesn't come back.
- [ ] Leave the Mac idle on power with Cohere downloaded; teacher findings appear. Unplug and check that the teacher stops.
- [ ] Australian, British and American spelling in prose; no change in a terminal, code editor, or in backticks.
- [ ] Swear words come out as said with every model.
