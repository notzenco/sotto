# Sotto

Sotto is on-device dictation for the Mac. Hold Right Command, speak, and let go. The text lands in the field you were typing in. Audio never leaves the machine, and Sotto learns the words it gets wrong.

It is a menu-bar app with no account and no cloud service. Speech is transcribed on the Mac by a model you choose: NVIDIA Parakeet TDT 0.6B v2 by default, other Parakeet models or Cohere Transcribe through [FluidAudio](https://github.com/FluidInference/FluidAudio) on Core ML, or Apple's built-in dictation. While you talk, an animated indicator follows your voice. Apple's provisional words can appear in a caption if you turn them on.

This is an early prototype. It is English only and has been run on one Apple silicon Mac with macOS 27.2.

## Using it

| Action | What happens |
|---|---|
| Hold Right Command, then release | Listens while held and inserts the text on release. |
| Tap Right Command (under 180 ms) | Nothing. A stray tap never inserts. |
| Double-tap Right Command | Listens hands-free until the next press. |
| Press another key while holding | Treated as a shortcut, so the take is dropped. |
| Esc | Cancels the take, including while Sotto is still working after you let go. Nothing is inserted. |
| Menu bar → Dictate | Starts or stops a hands-free take. |
| Settings → Shortcut → Chord | Records your own push-to-talk shortcut, which works alongside Right Command. |

The indicator shows a tick when text is inserted. If it cannot insert, it shows a short message, such as "Won't type into a password field" or "You moved away, so it's kept for Copy Last". Menu bar → Copy Last copies the last transcript.

If you start a new take before the last one has finished, the earlier take's text still goes in, but the indicator only shows the newer take.

**Modes.** Sotto picks a mode from the focused app. Settings → Speech → Mode can force one.

- **Prose** is used in mail, chat, browsers, Word and everything else. It drops fillers ("um", "uh"), capitalises sentences, and turns spoken punctuation into marks ("comma", "period", "question mark", "new paragraph"). One hold is one sentence: a take that ends without a closing mark gets a full stop.
- **Literal** is used in terminals and code editors. It never rewrites. Symbol words become symbols ("dot", "slash", "underscore", "open paren"), and "word dot" types the word "dot" itself.

**Back-to-back takes.** Sotto reads the few characters before the cursor and fits each take to them. It adds a space after a word or a closing mark, but not at the start of a field, after a space or new line, or after an opening bracket or quote. In Prose, a take that continues a sentence (after a word, number, comma or semicolon) starts in lowercase, unless its first word is "I", an acronym, one of your Names, a capitalised word from Your words or Learned, or a name. In fields that hide their text, Sotto assumes you're continuing when its last take went into the same field less than 3 minutes earlier. Terminals always use that fallback.

**Names.** Settings → Dictionary → Names maps what Sotto heard to how you spell it. A deleted spelling is remembered as deleted, so the same phrase can't be added again.

**Spelling.** Settings → Speech → Spelling is Australian (the default), British or American. After formatting, Prose text is respelled word by word, so "make the button color darker" becomes "make the button colour darker", keeping each word's case. Literal mode is never respelled. In Prose, words that look like code are skipped: anything inside backticks, camelCase and snake_case words, dotted names such as `file.color`, all-caps words, URLs, file paths, flags, `#tags`, `$variables`, `@handles` and words with digits. Your Names win over spelling. Swearing always comes out exactly as said.

**Inserting text.** Mail and most other apps get the text written through Accessibility, with a paste as the fallback. Chat apps, code editors, browsers, Word and remote desktops always get a paste. The clipboard is borrowed and restored afterwards, unless something else changed it in the meantime. Terminals get typed characters, because a paste can wedge some programs. Password fields are refused, and so is pasting or typing while secure input is on. If focus moved away during the take, the text is kept for Copy Last instead of going into the wrong field.

## Speech models and learning

**Typing model.** Settings → Speech lists the models that can type:

| Model | Size | Notes |
|---|---|---|
| Parakeet TDT 0.6B v2 | About 470 MB | The default. English. |
| Parakeet Ultra | About 630 MB | FluidAudio's most accurate Parakeet. |
| Phonon-2 | About 360 MB | The fastest Parakeet. English only. |
| Parakeet TDT 0.6B v3 | About 480 MB | 25 languages, more varied training voices. |
| Cohere Transcribe | About 1.8 GB | Slower and very accurate. Takes no hint words. |
| Apple English | Built in | Apple's dictation, in the English that matches the spelling setting. |

Each row shows whether the model is in use, downloaded, downloading, or preparing, or offers a Download button. A downloaded model other than the chosen one can be deleted. Apple English is part of macOS, so it has nothing to download or delete. Choosing a model that isn't downloaded downloads it. Its first load compiles it for the Neural Engine, shown as "Preparing…", which can take a minute or more. Sotto keeps typing with the previous model until the new one is ready, and only then saves the choice. Only the typing model stays loaded.

**Hint words.** Words Sotto has learned, and words you add under Your words, are passed to the typing model as hint words. Parakeet models use FluidAudio's custom vocabulary, which rescores the text against the audio before changing a word, so a real "Maggie" stays "Maggie". It needs a separate model of about 100 MB, downloaded the first time a hint word exists. Apple English gets the words as contextual strings. Hint words are never blind text replacements.

**Learning.** Sotto learns from three kinds of evidence. Differences in case and punctuation never count, and a change longer than four words is treated as a rewrite. Compare picks and the teacher also ignore spelling variety ("color" and "colour" count as the same word). Your own fixes don't yet, so respelling a word by hand can be learned; delete it under Learned if that happens.

- **Your fixes.** About 20 seconds after inserting, and when your next dictation starts within 2 minutes, Sotto reads the field back through Accessibility. If you changed one short phrase to something that sounds like it, such as "Madgie" to "my G", the word is learned at once. Fields that hide their text are skipped, and password fields are never read.
- **Compare picks.** Your final choice for each clip in the Compare window is learned once, when the window closes or Sotto quits.
- **The teacher.** Settings → Speech → Teacher picks a slower model that rechecks kept clips when you haven't dictated for 5 minutes and the Mac is on mains power. A phrase it hears differently on two different clips is learned. It stops when you dictate, unplug, or open Compare. The default teacher is Cohere Transcribe, but Sotto never downloads it on its own; only its Download button does. Off turns the teacher off.

Learned words appear under Settings → Dictionary → Learned. Deleting one stops it being learned again automatically. Adding it under Your words, or picking it again in Compare, brings it back.

**Compare.** Settings → Speech → Compare… opens a window with your kept clips, newest first. Each clip has a play button and every downloaded model's version, with your hint words applied where the model takes them. Models that haven't seen a clip run while the window is open, one at a time. Click the version that matches what you said, or type the right text. A running score shows how often each model was right, ignoring spelling variety. The typing model is shown and scored on its text after hint words, which is what you got.

## Indicator and Settings

The indicator has three styles:

- **Pill** is a capsule with bars that follow your voice.
- **Notch** is a black tab at the top centre, with a recording dot and bars. It wraps around the camera notch on displays that have one. If the tab would cover the line you're typing on, that take uses the Pill at the bottom instead.
- **Dot** is a small light with a glow that pulses with your voice.

A lock marks hands-free listening. Working dots appear while Sotto processes the take. A tick or a problem message follows. The indicator lets clicks through and does not take focus. When Sotto knows where your text cursor is, the indicator moves to the other edge of the screen rather than cover the line you're typing on.

Settings → Indicator has a live preview. Choose a style, size (80–150%), and bar colour: paper, white, blue, green, pink, orange or a custom colour. Pill and Dot can sit at the bottom centre, top centre or text cursor. If the cursor position is unavailable, they fall back to the bottom centre. Pill also has Dark, Glass and Light backgrounds. Choose the display with the mouse pointer or the main display; cursor placement uses the cursor's display when available. "Show words as you talk" adds a provisional caption while listening.

The default is a dark Pill at the bottom centre, at 100% size, with paper bars, on the display with the mouse pointer. Words are off. With Reduce Motion on, the level changes opacity instead of bouncing.

Open Settings from the menu bar, with ⌘, while Sotto is in front, or by opening Sotto again from Finder or Spotlight. The window has a sidebar and remembers the last category. Sotto shows a Dock icon while Settings is open, so the window reliably comes to the front.

| Category | Contents |
|---|---|
| General | Open Sotto at login. |
| Shortcut | Right Command instructions, the chord recorder and an Accessibility fix button when needed. |
| Indicator | Style, position, size, colour, background, words and display, with a live preview. |
| Microphone | Input device, "Keep the first syllable" and a level meter. The meter only runs while this page is showing and the microphone is open. |
| Speech | Automatic, Prose or Literal mode; the typing model list with Download, Preparing, Retry and Delete; Teacher; Spelling; Compare models with Keep audio, the kept clip count, Delete All and Compare…. |
| Dictionary | Learned words with where each came from and Delete; Your words; Names (heard → written). |
| History | Off or 24 hours, with recent transcripts and a Copy button for each. |
| Privacy & Permissions | Current Microphone and Accessibility status, buttons to request access or open System Settings, and the privacy statement, which follows Keep audio. |
| About | App version, a credit for each speech model, and the spelling list's credit and full licence. |

## Requirements

- macOS 26 or later. Live words in the indicator's caption use Apple's `SpeechAnalyzer`.
- Xcode 27. This was built with Xcode 27 beta 6 (Swift 6.4), in Swift 6 language mode with complete concurrency checking.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.45 or later. `project.yml` is the source of truth for the Xcode project.
- An Apple Development signing certificate (see [Signing](#signing)).
- About 470 MB of disk space for the default speech model, which downloads on first launch, and about 100 MB more for hint words once Sotto has one. Other models download only when you ask.

## Build and run

```sh
xcodegen generate
xcodebuild -project Sotto.xcodeproj -scheme Sotto -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Sotto.app
```

Run the unit tests with the same command, using `test` in place of `build`.

`Sotto.xcodeproj` is generated. Edit `project.yml` and run `xcodegen generate` again, rather than changing build settings in Xcode.

## Signing

The app is signed with an Apple Development certificate (`CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` in `project.yml`). To build it under your own account, change `DEVELOPMENT_TEAM` to your team ID.

Don't switch back to ad-hoc signing (`-`). An ad-hoc app is identified by the hash of its code, which changes on every build. macOS then treats each rebuild as a new app, so the Accessibility and Microphone grants stop applying. The switch in System Settings still looks on, but Right Command never arrives. A certificate identity keeps the same code requirement, and the same grants, across builds.

A certificate signature also turns on the hardened runtime. Under the hardened runtime, macOS denies the microphone without prompting unless the app has the `com.apple.security.device.audio-input` entitlement. That entitlement is in `App/Sotto.entitlements`.

## Permissions

Sotto needs two permissions. It asks for both on first launch.

- **Microphone**, to hear you.
- **Accessibility**, so macOS delivers Right Command to Sotto and lets it insert text. Turn Sotto on in System Settings → Privacy & Security → Accessibility.

Until Accessibility is on, Sotto opens its Settings window on Privacy & Permissions at launch, and the menu shows "Right Command needs permission".

## How it works

1. **Hotkey.** A listen-only event tap (`HotkeyMonitor`) watches modifier changes for the right-hand Command device bit, plus Escape and chord keys. `HoldTracker` turns presses and releases into start, finish, lock and cancel. A 30 ms poll of the modifier state stands in for the tap only while Accessibility is off.
2. **Capture.** `AudioCapture` taps the microphone in the hardware's own format and resamples it to 16 kHz mono. With "Keep the first syllable" on, the engine stays running and keeps the last 300 ms in an in-memory ring. That way the start of a word spoken as you press the key is not lost.
3. **Live line.** `LiveLine` feeds the same audio to Apple's `SpeechAnalyzer`, using `DictationTranscriber` in the English that matches the spelling setting, with hint words as contextual strings. Its provisional words appear only in the indicator's caption while listening, when "Show words as you talk" is on. When Apple English types, this session's final text is the result.
4. **Transcription.** On release, the whole take goes to the typing model through `ModelLibrary` (`App/Speech/`), which owns one engine per model behind the `SpeechEngine` protocol: `ParakeetFamilyEngine`, `CohereEngine` and `AppleEngine`. `HintBooster` then rescores Parakeet text against the hint words. If the typing model returns no transcript, Apple's live text is used instead; otherwise the typed text doesn't wait for Apple's session. Until the model is ready, available live text is kept for Copy Last and is not inserted. The indicator says "Still downloading the speech model".
5. **Formatting.** `TranscriptFormatter` applies Prose or Literal rules, `SpellingConverter` respells Prose, then `Rulebook` applies your Names. `InsertJoin` fits the result to the text before the cursor, which `TextInserter` reads through Accessibility.
6. **Insertion.** `InsertPlanner` picks Accessibility, paste, typing or refusal for the focused app, and `TextInserter` carries it out. The indicator shows a tick on success or a problem message if the text could not be inserted.
7. **Learning.** With Keep audio on, `ClipStore` saves the take's audio and record. `FixWatcher` reads the field back for your fixes, `TeacherScheduler` runs the teacher, and the Compare window (`App/Compare/`) runs every downloaded model. `PhraseAligner`, `FixDetector` and `SoundAlike` find the misheard phrases, and `Lexicon` decides when a word is learned.

### Layout

| Path | Contents |
|---|---|
| `Core/` | `SottoCore`, a static library of pure logic: hold timing, modes and app classes, formatting, Names, spelling conversion and its word list, joining takes to the text before the cursor, insert routing, the pre-roll ring, indicator settings, states, layout, bars and level smoothing, the speech model list, clip records and Compare scoring, phrase alignment, fix detection and the learned-word lexicon. |
| `Tests/` | Unit tests for `SottoCore`. |
| `App/` | The menu-bar app: audio, hotkey, live line, text insertion, clip storage, the fix watcher, the teacher, menus and storage. |
| `App/Speech/` | The speech engines behind one protocol, the model library and hint-word rescoring. |
| `App/Compare/` | The Compare window, its model runner, picks and clip playback. |
| `App/Indicator/` | Indicator views, panel and text cursor lookup. |
| `App/Settings/` | Sidebar Settings window and its panes. |
| `scripts/` | `generate-spelling-table.py`, which builds `Core/SpellingTable.swift` from VarCon. |
| `project.yml` | XcodeGen definition of the three targets and the `Sotto` scheme. |

## Privacy

- **Audio is kept on this Mac by default.** With Settings → Speech → Keep audio on (the default), each finished dictation's audio is saved in `~/Library/Application Support/Sotto/Clips/`, with a small JSON record of what the typing model heard and what was typed. Clips are used only on this Mac, by Compare and the teacher, and are never sent anywhere. They are deleted after 7 days, checked every minute. Cancelled takes, takes with nothing heard and takes aimed at a password field aren't kept. Turning Keep audio off stops new clips and asks whether to delete the existing ones, and Delete All removes them at once. The statement in Privacy & Permissions follows the toggle.
- The pre-roll ring stays in memory. It is overwritten continuously and never written to disk.
- Transcription and learning run on this Mac. Nothing is sent to a server. Network use is for model downloads, including Apple's speech assets when needed.
- History is off by default. When it is on (24 hours), transcripts older than a day are dropped the next time you dictate.
- Dictation settings, Names, learned words and Your words, history and clips live in `~/Library/Application Support/Sotto/`. FluidAudio models (Parakeet, Cohere Transcribe and the hint-word model) live in `~/Library/Application Support/FluidAudio/Models/`. Apple's speech assets are managed by macOS. The last Settings category and window frame use macOS preferences.

## Troubleshooting

**Right Command does nothing, but Accessibility looks on.** The grant belongs to an older build. Select Sotto in the Accessibility list and remove it with "−", then turn it on again. Alternatively, run `tccutil reset Accessibility app.sotto.desktop` and relaunch. This should only happen once after a signing change.

**Microphone is never requested.** Check that the built app has the audio-input entitlement:

```sh
codesign -d --entitlements - build/DerivedData/Build/Products/Debug/Sotto.app
```

**Bluetooth headsets.** Opening the microphone on AirPods switches them to a lower-quality call profile (24 kHz). Capture follows the hardware format, so this works, but playback through the headset sounds worse while Sotto holds the microphone. Turn off "Keep the first syllable" to open the microphone only while you dictate.

**Debug log.** Hotkey and permission events are appended to `/tmp/sotto-hotkey.log`. Timing for each take is logged under the subsystem `app.sotto.desktop`:

```sh
log show --last 10m --info --predicate 'subsystem == "app.sotto.desktop"'
```

## Credits

- Speech models: [NVIDIA Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) and v3 (CC-BY-4.0), Moondream Parakeet Ultra (CC-BY-4.0), Fermion Research Phonon-2 (CC-BY-4.0, based on Parakeet TDT 0.6B v3) and Cohere Labs Cohere Transcribe 03-2026 (Apache-2.0), all run through FluidAudio. About lists each credit.
- Spelling list: adapted from VarCon by Kevin Atkinson and Benjamin Titze, from word lists by Geoff Kuenning (a modified subset of common words). Its full licence notice is in About and in `Core/SpellingTable.swift`.
- [FluidAudio](https://github.com/FluidInference/FluidAudio) by FluidInference, Apache License 2.0.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus, MIT License.

## License

Sotto's own code is MIT; see [`LICENSE`](LICENSE). The speech models, spelling list and dependencies keep their own licences, listed under Credits.
