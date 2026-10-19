# Sotto

Sotto is on-device dictation for the Mac. Hold Right Command, speak, and let go. The text lands in the field you were typing in. Audio never leaves the machine.

It is a menu-bar app with no account and no cloud service. Speech is transcribed by NVIDIA Parakeet TDT 0.6B v2 running through [FluidAudio](https://github.com/FluidInference/FluidAudio) on Core ML. While you talk, a small slip under the menu bar shows Apple's live transcription as a provisional line.

This is an early prototype. It is English only and has been run on one Apple silicon Mac with macOS 27.2.

## Using it

| Action | What happens |
|---|---|
| Hold Right Command, then release | Listens while held and inserts the text on release. |
| Tap Right Command (under 180 ms) | Nothing. A stray tap never inserts. |
| Double-tap Right Command | Listens hands-free until the next press. |
| Press another key while holding | Treated as a shortcut, so the take is dropped. |
| Esc | Cancels the take. |
| Menu bar → Dictate | Starts or stops a hands-free take. |
| Settings → Chord | Records your own push-to-talk shortcut, which works alongside Right Command. |

The slip shows the result: the inserted text, or the reason it was kept instead (for example "password refused" or "focus changed"). Menu bar → Copy Last copies the last transcript.

**Modes.** Sotto picks a mode from the focused app. Settings → Mode can force one.

- **Prose** is used in mail, chat, browsers, Word and everything else. It drops fillers ("um", "uh"), capitalises sentences, and turns spoken punctuation into marks ("comma", "period", "question mark", "new paragraph").
- **Literal** is used in terminals and code editors. It never rewrites. Symbol words become symbols ("dot", "slash", "underscore", "open paren"), and "word dot" types the word "dot" itself.

**Names.** Settings → Names maps what Sotto heard to how you spell it. A deleted spelling is remembered as deleted, so the same phrase can't be added again.

**Inserting text.** Mail and most other apps get the text written through Accessibility, with a paste as the fallback. Chat apps, code editors, browsers, Word and remote desktops always get a paste. The clipboard is borrowed and restored afterwards, unless something else changed it in the meantime. Terminals get typed characters, because a paste can wedge some programs. Password fields are refused, and so is pasting or typing while secure input is on. If focus moved away during the take, the text stays in the slip instead of going into the wrong field.

## Requirements

- macOS 26 or later. Live words in the slip use Apple's `SpeechAnalyzer`.
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

Until Accessibility is on, Sotto opens its Settings window and the Accessibility pane at launch, and the menu shows "Right Command needs permission".

## How it works

1. **Hotkey.** A listen-only event tap (`HotkeyMonitor`) watches modifier changes for the right-hand Command device bit, plus Escape and chord keys. `HoldTracker` turns presses and releases into start, finish, lock and cancel. A 30 ms poll of the modifier state stands in for the tap only while Accessibility is off.
2. **Capture.** `AudioCapture` taps the microphone in the hardware's own format and resamples it to 16 kHz mono. With "Keep the first syllable" on, the engine stays running and keeps the last 300 ms in an in-memory ring. That way the start of a word spoken as you press the key is not lost.
3. **Live line.** `LiveLine` feeds the same audio to Apple's `SpeechAnalyzer`. Its words only appear in the slip.
4. **Transcription.** On release, the whole take goes to Parakeet (`ParakeetEngine`). If Parakeet hears nothing, Apple's live text is used instead. Until the model has downloaded, a take is only shown in the slip and kept for Copy Last. It is not inserted.
5. **Formatting.** `TranscriptFormatter` applies Prose or Literal rules, then `Rulebook` applies your spellings.
6. **Insertion.** `InsertPlanner` picks Accessibility, paste, typing or refusal for the focused app, and `TextInserter` carries it out.

### Layout

| Path | Contents |
|---|---|
| `Core/` | `SottoCore`, a static library of pure logic: hold timing, modes and app classes, formatting, spellings, insert routing, the pre-roll ring. |
| `Tests/` | Unit tests for `SottoCore`. |
| `App/` | The menu-bar app: audio, speech engines, hotkey, text insertion, the slip, settings and storage. |
| `project.yml` | XcodeGen definition of the three targets and the `Sotto` scheme. |

## Privacy

- Audio stays in memory. The pre-roll ring is overwritten continuously and never written to disk.
- Transcription runs on this Mac. Nothing is sent to a server. The only network use is the one-time model download.
- History is off by default. When it is on (24 hours), transcripts older than a day are dropped the next time you dictate.
- Settings, spellings and history live in `~/Library/Application Support/Sotto/`. The model lives in `~/Library/Application Support/FluidAudio/Models/`.

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
