# Sotto: accent and slang

Status: approved and implemented · 19 October 2026. The plan is `docs/superpowers/plans/2026-10-19-accent-and-slang.md`. See "Decisions made during implementation" for where the build refined this design.

This is project 2 of the round that started with the new look. The order agreed on 19 October 2026:

1. **The new look**: done, merged at `ad30c34`.
2. **Accent and slang** (this document): choosing the speech model, testing models on the owner's own voice, a smart model that teaches the fast one, learning from corrections, hint words, Australian spelling, and swearing kept as said.
3. **Smart features, on-device** (`2026-10-19-smart-features-design.md`): snippets, styles per app, backtrack, numbered lists, command mode.
4. **Quality of life** (`2026-10-19-quality-of-life-design.md`): choosing the key, the AirPods microphone, lowering music, sounds, auto-stop, hiding the menu-bar icon, longer history, usage stats.

## Why

Sotto is the owner's free, private, better version of Wispr Flow. The owner is Australian and speaks casually, with slang. Parakeet TDT 0.6B v2 mishears them. On 19 October 2026 they said "my G" three times and got "My gee", "Madgie" and "my G". They dictate mostly into AI coding agents (T3 Code, Codex) and Discord.

Wispr Flow learns the words you correct and sends your audio to its servers. Sotto should learn faster and keep everything on the Mac.

## Already done before this project

Merged into `main` together with this design, from branch `smart-spacing`:

- **Spacing and case across dictations** (`Core/InsertJoin.swift`). Sotto reads the text before the cursor and adds a leading space, or lowercases the first word mid-sentence. Names, "I", acronyms and Dictionary spellings keep their capitals.
- **One hold is one sentence.** A prose dictation that ends in a letter or a number gets a full stop.

Build on these. Don't redo them.

## Goals

1. Let the owner choose the speech model that types (the **typing model**) from a list of local models.
2. Keep the audio of each dictation on the Mac for a while, so models can be compared on the owner's real voice.
3. A **Compare** window where the owner hears each kept clip, sees every downloaded model's version, and picks the right one. Sotto keeps a running score.
4. A slower, more accurate **teacher model** rechecks kept clips in the background and finds words the typing model got wrong.
5. Learn from the owner's own corrections made right after Sotto types.
6. **Learned words** start working on their own, without approval, through hint words the typing model listens for.
7. The owner can add their own slang and names as hint words.
8. Australian spelling by default, with British and American as options.
9. Swearing comes out exactly as said.

## Non-goals

- Retraining or fine-tuning any model's weights. "Teaching" here means hint words, not new weights.
- Whisper, WhisperKit, or the large LLM-based recognisers (Granite Speech, Canary-Qwen, Qwen3-ASR). They wait until the models below have been tried on the owner's voice.
- Languages other than English.
- Rewriting text that Sotto already typed, after the teacher finishes.
- Anything in projects 3 and 4.

## Anti-goals

Any of these would make the project a failure, even if everything else works:

- **Slower typing.** With the same typing model, the time from releasing the key to the text appearing gets noticeably longer than today. Hint checks must not add noticeable delay in the common case.
- **Audio leaves the Mac,** or audio is kept while "Keep audio" is off, or a clip outlives its retention period.
- **Code gets "corrected".** Spelling changes alter text in Literal mode, such as `color` in CSS becoming `colour`.
- **A bad learned word sticks.** A learned word can't be removed, or comes back after the owner deletes it.
- **Battery drain.** The teacher runs while the Mac is on battery or in use.
- **Censoring.** Any swear word comes out masked, changed or dropped.
- **Regressions.** Right Command, the event tap, signing, entitlements, audio capture, smart spacing or the indicator stop working.

## Speech models

### The list

Offer these as typing models in the Speech pane. All run on the Mac, and none needs a new package dependency.

| Model | Through | Notes |
|---|---|---|
| Parakeet TDT 0.6B v2 | FluidAudio (`AsrModelVersion.v2`) | Today's model and the default until the owner picks another. English. |
| Parakeet Ultra | FluidAudio (`.ultra`) | FluidAudio's most accurate Parakeet. About 630 MB. |
| Phonon-2 | FluidAudio (`.phonon2`) | Fastest Parakeet, English only. About 360 MB. |
| Parakeet TDT 0.6B v3 | FluidAudio (`.v3`) | 25 languages, more varied training voices. About 480 MB. |
| Cohere Transcribe | FluidAudio (`CoherePipeline`) | Near the top of the public English accuracy leaderboard. About 1.8 GB, slower. FluidAudio's `transcribeLong` already handles clips over its 35-second window. |
| Apple English (Australian, British or American) | `SpeechAnalyzer` with `DictationTranscriber`, in the locale that matches the spelling setting (`en_AU` by default) | Built into macOS and already installed on the owner's Mac. Accepts hint words through `AnalysisContext.contextualStrings`. |

Each row shows its state: in use, downloaded, downloading with progress, preparing, or a Download button. A downloaded model can be deleted, except the one in use. Only the typing model stays loaded in memory.

The first load of a model compiles it for the Neural Engine, which can take about a minute (Phonon-2's docs say so). Show "Preparing…" while that happens, and keep typing with the previous model until the new one is ready. Later switches to a model that has been prepared before should take a few seconds at most.

**Apple's engine reuses the live-caption session.** Every dictation already runs Apple's transcriber for live captions (`LiveLine`), and its text is the fallback when the typing model returns nothing. When Apple is the typing model, use that session's final text directly, with no second pass. When another model types, the Apple session stays the fallback. Its locale follows the spelling setting (below).

FluidAudio's own docs and benchmarks are in its checkout under `Documentation/` (`Models.md`, `Benchmarks.md`, `ASR/CustomVocabulary.md`, `ASR/Cohere.md`). The pinned revision is in `project.yml`.

### Teacher model

A second picker, "Teacher", chooses the model that rechecks clips in the background. It can be any model other than the typing model, or Off. Picking a model that isn't downloaded doesn't download it; only its Download button does.

It defaults to Cohere Transcribe, but Sotto doesn't download 1.8 GB on its own. Until the owner downloads it, the Teacher row shows "Download Cohere Transcribe (1.8 GB) to start background learning" with a button. Learning from the owner's fixes and from Compare works without a teacher.

### One interface for every engine

All engines sit behind one Swift protocol in the app: prepare, transcribe samples with optional hint words, report download progress and phase, unload. The list of models (id, display name, size, languages, whether it accepts hints, licence credit) lives in `SottoCore` as plain data, so it can be tested and ported.

## Keeping audio

- **Keep audio for comparing models**: a toggle, on by default, in the Speech pane under "Compare models".
- Each finished dictation's 16 kHz mono samples are saved to `~/Library/Application Support/Sotto/Clips/` with a small JSON record: id, date, app bundle id and website, the typing model's id, what the typing model returned **before** hint words were applied, what it returned after, and what Sotto finally typed. The teacher and Compare compare against the text from before hints, so the model's own mistakes aren't mixed up with hint corrections.
- Clips are deleted after **7 days**. "Delete all" removes them at once. Turning the toggle off stops saving new clips and asks whether to delete the existing ones.
- Cancelled takes and takes with nothing heard aren't kept.
- The Privacy pane statement changes with the toggle. When it's on, it says audio is kept on this Mac for 7 days to improve recognition and is never sent anywhere.

## The Compare window

Opened from "Compare…" in the Speech pane. It's a separate window.

- Clips are listed newest first. Each has a play button, the time, the app and the length.
- Under each clip is every downloaded model's version. Models run with the current hint words where they accept them, so the score reflects what the owner would actually get.
- Models that haven't run on a clip yet run while the Compare window is open, whatever the power state, with overall progress shown. Load one model at a time, run it over the waiting clips, then unload it before the next. Stop when the window closes or a dictation starts.
- The owner clicks the version that matches what they said, or types the correct text if none does.
- A running score shows how often each model was right.
- The owner's picks and typed corrections are saved. They also feed learning (below) as the strongest kind of evidence.

## Learning

### Where the evidence comes from

1. **Teacher disagreements.** When the Mac is idle (no dictation for 5 minutes) and on mains power, the teacher transcribes kept clips it hasn't seen. Sotto aligns the teacher's words with the typing model's words and records each substituted phrase, such as "Madgie" against "my G". It stops as soon as a dictation starts or power is unplugged, and unloads the teacher when it's done.
2. **The owner's own fixes.** After Sotto types into a field, it remembers what it typed and where. It reads that field's text again through Accessibility about 20 seconds after inserting, and when the next dictation starts (in any field), within 2 minutes of inserting. No focus watching is needed. An edit counts as a fix only when all of these hold:
   - the typed text is still there apart from one changed span;
   - that span is at most four words, replaced by at most four words, and isn't a pure deletion;
   - the old and new phrases sound alike (a phonetic or spelling similarity check in `SottoCore`), so rewording such as "great" → "awesome" doesn't count.

   For example, "Margie" → "my G" counts. Fields that don't expose their text are skipped. Never read secure fields.
3. **Compare picks.** A pick or typed correction in the Compare window, against the typing model's version.

Alignment and phrase extraction are plain logic in `SottoCore`, with unit tests. Ignore differences in case, punctuation and spelling variety. Ignore a substitution longer than four words, which is more likely a rewrite than a mishearing.

### When a word is learned

A pair becomes a **learned word** when any of these is true:

- the owner fixed it once;
- the owner picked or typed it once in Compare;
- the teacher found the same pair on at least two different clips.

Learned words apply immediately, with no approval.

### How a learned word is used

- **Hint words.** The learned word's written form (for example "my G") joins the typing model's hint list. Parakeet models use FluidAudio's custom vocabulary (`VocabularyBoostingSession`, CTC rescoring with a separate CTC encoder, see `ASR/CustomVocabulary.md`), with the misheard forms as aliases. That encoder is an extra download of about 100 MB, fetched the first time a hint word exists. FluidAudio's docs confirm v2 and v3. Ultra and Phonon-2 share v3's tokenizer and should work, but check. Any model where it doesn't work is marked "No hint words" in the list.
- The Apple model gets the list as contextual strings (`AnalysisContext.contextualStrings`). Check that `SpeechTranscriber` honours them. If it doesn't, use `DictationTranscriber`, which does and also supports `en_AU`, for the Apple engine and live captions.
- Cohere Transcribe takes no hints.
- The rescoring checks the audio before changing anything, so a real "Maggie" shouldn't become "my G". Use FluidAudio's preflight check so the CTC pass only runs when a dictation might contain a hint word.
- Learned words are **not** blind text replacements.

### The Dictionary pane

It gets three sections:

- **Learned**: each learned word, its misheard forms, where it came from (your fix, Compare, or the teacher) and how often. A Delete button. Deleting blocks that written form from being learned again automatically, by the teacher or by fix detection, the same way `Rulebook` remembers deleted names today. Adding it by hand under "Your words", or picking it in Compare, unblocks it.
- **Your words**: hint words the owner types in, such as slang, names and brands. Add and Delete.
- **Names**: today's "when you say → write" rules, unchanged.

## Spelling

- **Spelling**: Australian (default), British or American, in the Speech pane.
- After formatting, prose-mode text is converted word by word with a US ↔ UK/AU word list in `SottoCore`. Preserve each word's case. Australian follows British spelling, with any known Australian exceptions.
- **Literal mode is never converted.**
- Prose in every app is converted, including the coding agents (T3 Code, Codex) where the owner dictates most. Words that look like code are skipped: anything inside backticks, camelCase and snake_case words, dotted names such as `file.color`, all-caps words, URLs and file paths. So "make the button color darker" becomes "make the button colour darker", but `` `color` `` stays as it is.
- The bundled word list must have a licence that allows redistribution in a free app. Credit it in About if its licence asks.
- Apple's live captions switch from `en-US` to the locale matching the spelling setting (`en_AU`, `en_GB` or `en_US`).

## Swearing

Swearing is kept exactly as said, with no option to change it. No engine may mask profanity. For the Apple engine, leave the etiquette-replacement transcription option off (it's opt-in). Add a test that the formatter, spelling conversion and Rulebook leave common swear words untouched.

## Settings summary

| Pane | Rows |
|---|---|
| Speech | Mode (existing). Typing model list. Teacher. Spelling. Compare models: Keep audio, clip count, Delete all, Compare… |
| Dictionary | Learned, Your words, Names. |
| Privacy & Permissions | The statement follows the Keep audio toggle. |
| About | A credit for every model in the list, and the spelling list if needed. |

## Constraints

- macOS 26 or later, Swift 6 language mode, SwiftUI plus AppKit. No new package dependencies. FluidAudio may be bumped to a newer revision only if needed, with the reason noted.
- `project.yml` is the source of truth. Regenerate with XcodeGen. Don't change signing, team or entitlements.
- New settings fields decode with defaults when missing. Add tests that decode today's `settings.json` and `rulebook.json`.
- **Portability.** `SottoCore` imports only Foundation. All new logic that doesn't need Apple frameworks goes there with tests: the model list, clip records and retention, alignment, learning thresholds, spelling conversion. Engines sit behind one interface. Stored data (clips' JSON records, learned words, your words, settings) is plain JSON. This keeps a later Rust port mostly mechanical.
- Leave the hotkey path alone: `HotkeyMonitor`, `RightCommand`, and `AppModel`'s `watchHotkey`, `hotkeyTick`, `noteRightCommand` and `maintainTap`.
- Keep the `AudioCapture` tap on `inputNode.inputFormat(forBus: 0)`.

## Decided by the owner

- A model picker in Settings.
- Keep dictation audio on the Mac to compare models on their own voice.
- A fast typing model, with smarter models teaching it in the background.
- Learned words apply on their own, without approval.
- One hold is one sentence.
- Stay in Swift for now, and keep the core portable.
- Australian spelling by default, British and American as options. Swearing kept as said.
- Spelling applies in the coding agents too, skipping words that look like code.

## Calls made in writing this up (the owner can overrule)

- The model list above. Parakeet v2 stays the default typing model until the owner switches.
- Cohere Transcribe is the default teacher, but it's only downloaded when the owner asks.
- Apple's engine reuses the live-caption session instead of running a second pass.
- Fix detection reads the field about 20 seconds after inserting and at the next dictation, within 2 minutes, and counts only small, similar-sounding replacements.
- Deleting a learned word blocks automatic relearning. Adding it by hand or picking it in Compare unblocks it.
- Compare runs while its window is open, one model at a time, with hint words on.
- Clip records keep the typing model's text from before hints.
- Keep audio is on by default, with 7-day retention.
- The teacher runs after 5 minutes without dictation, only on mains power.
- Learning thresholds: one fix, one Compare pick, or two teacher disagreements.
- Learned words work only as hint words, never as blind text replacements.
- Swearing has no setting.
- Apple's live captions follow the spelling setting's locale.

## Decisions made during implementation

The build refined this design in these places. Each was a ruling made on the owner's behalf. The owner can overrule any of them.

- **Apple's transcriber.** The Apple engine and live captions use `DictationTranscriber`. In a hand check, only it honoured contextual strings; `SpeechTranscriber` ignored them.
- **Apple's name.** The Apple model is called "Apple English (<locale>)", such as "Apple English (Australian)", because its locale follows the spelling setting.
- **Teacher downloads.** Picking a teacher that isn't downloaded doesn't download it. Only the Teacher row's Download button does.
- **Switching typing models.** Selecting a typing model that isn't downloaded downloads it, an explicit owner action. Typing stays on the old model until the new one is ready, and the choice is saved only once the switch succeeds, so a relaunch mid-download starts on the model that last worked.
- **Cohere's decoder.** Cohere Transcribe uses the published v2 decoder, because the v3 decoder files aren't published. A result with any window cut off at the decoder's token cap is discarded, so the teacher and Compare skip that clip rather than learn from truncated text.
- **Apple stays off the typing path.** The typed text doesn't wait for Apple's live captions unless Apple types, or the typing model returned nothing and Apple's text is the fallback.
- **Live caption locale.** After a spelling change, live captions keep the last installed locale until the new locale's asset has installed, then switch from the next take.
- **Compare learning.** Compare picks and typed corrections are learned once per clip, from the final choice, when the window closes or Sotto quits, so a misclick that's changed or cleared teaches nothing. A word deleted after the choice isn't learned back at close; one deleted before it is unblocked, as a Compare pick does.
- **Compare scoring.** The typing model is shown and scored on its text after hint words, which is what the owner got; the text from before hints stays the learning source. A model counts as right when its text matches the picked or corrected text, ignoring case, punctuation and spelling variety.
- **Spelling-insensitive learning.** The teacher and Compare share one alignment that maps every word to American spelling first, so "colour" against "color" is never learned.
- **Hint words keep punctuation.** FluidAudio's CTC replacements are applied to the raw text span by span, so punctuation around a boosted word stays as transcribed.
- **Capitals.** Your words and learned words written with a capital, such as "Wispr", keep it when a dictation continues a sentence.
- **Clip privacy and retention.** A take aimed at a password field, or made while secure input is on, never keeps its audio. Expired clips are pruned every minute as well as at launch and after each take, so none outlive 7 days on a Mac left running.
- **Spelling list.** The list comes from VarCon (2020.12.07): verified clusters at SCOWL level 60 or below, whole families dropped when any word depends on meaning, and swearing and slurs excluded. The generator is `scripts/generate-spelling-table.py`, and About shows the full licence notice. Prose words that start with `--`, `#`, `$` or `@`, or contain a digit, also count as code.

## Left to the builder

Within the anti-goals: file layout, the clip file format (WAV, CAF or raw floats), the alignment algorithm, the Compare window's exact layout, how download progress is shown, how idle and power state are detected, and which word list is bundled, subject to its licence.

## How we'll know it's done

- Unit tests cover the new `SottoCore` logic and pass, along with all existing tests.
- The app builds and installs with the Apple Development identity.
- Manual checks:
  - download, switch to and delete each model, and dictate with each one into T3 Code and Discord;
  - dictation speed with Parakeet v2 is the same as before;
  - clips appear, play in Compare and disappear after Delete all; turning Keep audio off stops new clips;
  - Compare runs every downloaded model and keeps score;
  - fix a misheard word right after Sotto types it, and see it in Learned; dictate it again and it comes out right;
  - delete a learned word and check that it doesn't come back;
  - leave the Mac idle on power and see teacher findings; unplug and check that the teacher stops;
  - Australian, British and American spelling in prose, and no change in a terminal or code editor;
  - say a few swear words and check they come out as said.

## Known gaps after the build

The final review left these for a later round. The owner can overrule any of them.

- **Fixes ignore spelling variety only partly.** Compare picks and the teacher compare words spelling-insensitively; fix detection doesn't yet, so editing "color" to "colour" by hand can be learned as a hint word.
- **Teacher picker during a switch.** While a new typing model downloads or prepares, the Teacher picker still lists it and hides the previous one, until the switch finishes.
- **Late secure input.** If secure input turns on after a take starts and the Accessibility write then fails, the take's clip is kept.
- **One-sound swaps.** Common swaps like "would" → "could" still count as fixes after one edit. A common-word guard is the next step.
