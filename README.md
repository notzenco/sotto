# Sotto

Sotto is on-device dictation for the Mac. Hold Right Command, speak, and let go. The text lands in the field you were typing in. Audio never leaves the machine.

It is a menu-bar app with no account and no cloud service. Speech is transcribed by NVIDIA Parakeet TDT 0.6B v2 running through [FluidAudio](https://github.com/FluidInference/FluidAudio) on Core ML. While you talk, an animated indicator follows your voice. Apple's provisional words can appear in a caption if you turn them on.

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

**Back-to-back takes.** Sotto reads the few characters before the cursor and fits each take to them. It adds a space after a word or a closing mark, but not at the start of a field, after a space or new line, or after an opening bracket or quote. In Prose, a take that continues a sentence (after a word, number, comma or semicolon) starts in lowercase, unless its first word is "I", an acronym, one of your spellings, or a name. In fields that hide their text, Sotto assumes you're continuing when its last take went into the same field less than 3 minutes earlier. Terminals always use that fallback.

**Names.** Settings → Dictionary → Names maps what Sotto heard to how you spell it. A deleted spelling is remembered as deleted, so the same phrase can't be added again.

**Inserting text.** Mail and most other apps get the text written through Accessibility, with a paste as the fallback. Chat apps, code editors, browsers, Word and remote desktops always get a paste. The clipboard is borrowed and restored afterwards, unless something else changed it in the meantime. Terminals get typed characters, because a paste can wedge some programs. Password fields are refused, and so is pasting or typing while secure input is on. If focus moved away during the take, the text is kept for Copy Last instead of going into the wrong field.

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
| Speech | Automatic, Prose or Literal mode; model status and Retry after a failure; English language. |
| Dictionary | Add or delete heard → written spellings. |
| History | Off or 24 hours, with recent transcripts and a Copy button for each. |
| Privacy & Permissions | Current Microphone and Accessibility status, buttons to request access or open System Settings, and the privacy statement. |
| About | App version and speech model credit. |

## Requirements

- macOS 26 or later. Live words in the indicator's caption use Apple's `SpeechAnalyzer`.
- Xcode 27. This was built with Xcode 27 beta 6 (Swift 6.4), in Swift 6 language mode with complete concurrency checking.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.45 or later. `project.yml` is the source of truth for the Xcode project.
- An Apple Development signing certificate (see [Signing](#signing)).
- About 450 MB of disk space for the speech model, which downloads on first launch.

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
3. **Live line.** `LiveLine` feeds the same audio to Apple's `SpeechAnalyzer`. Its provisional words appear only in the indicator's caption while listening, when "Show words as you talk" is on.
4. **Transcription.** On release, the whole take goes to Parakeet (`ParakeetEngine`). If Parakeet returns no transcript, Apple's live text is used instead. Until the model is ready, available live text is kept for Copy Last and is not inserted. The indicator says "Still downloading the speech model".
5. **Formatting.** `TranscriptFormatter` applies Prose or Literal rules, then `Rulebook` applies your spellings. `InsertJoin` fits the result to the text before the cursor, which `TextInserter` reads through Accessibility.
6. **Insertion.** `InsertPlanner` picks Accessibility, paste, typing or refusal for the focused app, and `TextInserter` carries it out. The indicator shows a tick on success or a problem message if the text could not be inserted.

### Layout

| Path | Contents |
|---|---|
| `Core/` | `SottoCore`, a static library of pure logic: hold timing, modes and app classes, formatting, spellings, joining takes to the text before the cursor, insert routing, the pre-roll ring, indicator settings, states, layout, bars and level smoothing. |
| `Tests/` | Unit tests for `SottoCore`. |
| `App/` | The menu-bar app: audio, speech engines, hotkey, text insertion, menus and storage. |
| `App/Indicator/` | Indicator views, panel and text cursor lookup. |
| `App/Settings/` | Sidebar Settings window and its panes. |
| `project.yml` | XcodeGen definition of the three targets and the `Sotto` scheme. |

## Privacy

- Audio stays in memory. The pre-roll ring is overwritten continuously and never written to disk.
- Transcription runs on this Mac. Nothing is sent to a server. Network use is for model downloads, including Apple's live speech assets when needed.
- History is off by default. When it is on (24 hours), transcripts older than a day are dropped the next time you dictate.
- Dictation settings, spellings and history live in `~/Library/Application Support/Sotto/`. The Parakeet model lives in `~/Library/Application Support/FluidAudio/Models/`. The last Settings category and window frame use macOS preferences.

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

- Speech model: [NVIDIA Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2), licensed CC-BY-4.0.
- [FluidAudio](https://github.com/FluidInference/FluidAudio) by FluidInference, Apache License 2.0.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus, MIT License.
