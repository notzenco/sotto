# Sotto: quality of life

Status: approved · 19 October 2026. Not yet implemented.

Project 4 of 4, after smart features (`2026-10-19-smart-features-design.md`). These are the owner's original "more features" list, minus snippets and per-app behaviour, which moved to project 3, plus usage stats.

Projects 2 and 3 are built and merged first. Plan this project against the code as it is after them: kept clips, the engine interface and the newer settings fields already exist.

## Why

These features make daily use smoother: the key the owner prefers, no call-quality audio when AirPods are in, music that gets out of the way, a sound to confirm what happened, hands-free dictation that stops by itself, a tidier menu bar, history that lasts, and a sense of how much Sotto is used.

## Goals

1. Choose the dictation key.
2. Use the Mac's microphone when AirPods (or another Bluetooth headset) are the input, so they don't drop to call-quality audio.
3. Lower music while dictating.
4. Start and stop sounds.
5. Auto-stop hands-free dictation after silence.
6. Hide the menu-bar icon.
7. History kept for 24 hours, 7 days or forever, as well as off.
8. Usage stats.

## Non-goals

- Pausing media through private APIs.
- Custom sound packs or importing sounds.
- Syncing history or stats anywhere.
- Changing how the push-to-talk chord works.

## Anti-goals

- **Hotkey regressions.** Right Command stops working, or any key choice misses presses, sticks down or fires during other shortcuts. This touches the hotkey path, so treat it with care and test every choice.
- **Sounds in the transcript.** The start sound is picked up by the microphone and transcribed, or cut into the kept clip.
- **Volume left low.** Music stays quiet after a dictation ends, is cancelled, or Sotto quits or crashes mid-dictation.
- **Stuck hands-free.** Auto-stop cuts the owner off mid-sentence during a natural pause.
- **Lost Sotto.** With the menu-bar icon hidden, the owner can't find a way back to Settings.
- **Lost history.** Changing the history setting deletes entries the owner meant to keep, or the old `historyHours` value doesn't migrate.
- **Breaking the AirPods fix.** `AudioCapture` stops using `inputNode.inputFormat(forBus: 0)` for its tap.

## Choosing the dictation key

- **Dictation key** in the Shortcut pane: Right Command (default), Right Option, Right Control, or Fn (Globe).
- Hold, double-tap for hands-free, the 180 ms stray-tap rule, chord cancelling and Esc all work the same for every choice.
- Generalise `RightCommand` into a key description in `SottoCore`. Right Option (device bits 0x40 right, 0x20 left) and Right Control (0x2000 right, 0x01 left) use the device bit, as Right Command does today. The Right Command keycode is also hard-coded in `HotkeyMonitor` and in `AppModel`'s fallback poller, and named in the menu's permission text. All of these follow the chosen key. `HoldTracker` is unchanged.
- **Fn (Globe)** has no device bit. Detect it by keycode 63 together with the Fn flag (0x800000), in both the event tap and the fallback poller, and ignore the Fn flag that macOS also sets on arrow and function keys. macOS may use Globe for the emoji picker, input sources or dictation. If Fn is chosen, the Shortcut pane explains how to set "Press 🌐 key to" to "Do nothing" in System Settings, with a button that opens that page. If testing shows Fn can't meet the "no missed or stuck presses" bar, leave it out of the list.
- The push-to-talk chord stays as an extra way to dictate.

## The Mac's microphone when AirPods are in

- **Use this Mac's microphone with Bluetooth headphones**: a toggle in the Microphone pane, on by default.
- When the input device is "System default" and the current default input is a Bluetooth device, capture from the built-in microphone instead. A specific device the owner picked is always used as picked.
- The microphone list and the level meter show which device is actually in use.
- When the built-in microphone isn't available (for example a closed MacBook lid with an external display), use the default input.

## Lowering music

- **While dictating, music**: Keep playing, Lower (default), in the Microphone pane. With Lower, a slider sets the level, 30% of the current volume by default.
- Lower the default output device's volume at the start of listening and restore it when listening ends, including on cancel and on quit.
- If the owner changes the volume during dictation, keep their new volume rather than restoring the old one.
- Skip lowering when the output is a Bluetooth headset in call mode, or the device has no settable volume.

## Sounds

- **Sounds**: on by default, with a volume slider, in the General pane.
- A soft start sound, a stop sound, and a distinct sound for problems. Done needs no extra sound beyond stop.
- Short, quiet sounds bundled with the app. They must be original or have a licence that allows redistribution.
- No sound may reach the transcript or the kept clip. That includes the stop sound: capture continues for about 60 ms after the key is released, before the samples are collected. For example, trim or ignore the captured audio while a sound plays, or play the stop sound only after capture has ended.

## Auto-stop after silence

- **Stop hands-free dictation after silence**: Off, 2, 3 (default) or 5 seconds, in the Shortcut pane.
- Only for hands-free takes. Held takes stop when the key is released, as today.
- Use voice activity detection, either FluidAudio's Silero VAD or the existing level meter, so background noise doesn't keep a take running forever. The silence timer starts only after some speech has been heard.

## Hiding the menu-bar icon

- **Show Sotto in the menu bar**: on by default, in the General pane.
- When it's turned off, a confirmation explains how to get back: open Sotto from Spotlight or Finder, which opens Settings.
- Today only reopening an already-running Sotto opens Settings (`applicationShouldHandleReopen`). A fresh launch shows nothing. With the icon hidden, a fresh launch by the owner must also open Settings. A launch at login must not.
- Dictation and problem messages work the same without the icon.

## History

- **Keep history**: Off, 24 hours, 7 days, Forever, in the History pane. Migrate today's `historyHours`: 0 to Off and 24 to 24 hours.
- Choosing a shorter period, or Off, when that would delete existing entries asks first and says how many entries will go. Cancelling keeps the previous setting. Today, choosing Off deletes everything without asking.
- **Clear history** removes all entries after a confirmation.
- Pruning runs at launch and after each dictation.
- History stays separate from kept audio clips, which keep their own 7-day rule from project 2.

## Usage stats

A section at the top of the History pane:

- words dictated this week and in total;
- number of dictations;
- time saved, estimated from words at 40 words per minute of typing minus time spent speaking;
- top apps by words.

Stats are counted as dictations happen and stored as plain JSON. They don't depend on history being on, and they keep counting when history is off. They hold no dictated text.

On first run, seed the dictation count from today's `dictationCount`, and words and top apps from any existing history entries.

## Constraints

- Same platform, signing and project-file constraints as projects 2 and 3. No new package dependencies.
- The hotkey path changes only for the key choice, with tests for each key's flag and keycode handling in `SottoCore`.
- New settings fields decode with defaults when missing, with tests on older `settings.json` files, including the `historyHours` migration.
- **Portability.** Key descriptions, retention rules, stats counting, volume-restore decisions and silence timing go in `SottoCore`, which imports only Foundation.

## Decided by the owner

The feature list itself: choosing the key, the Mac's microphone with AirPods, lowering music, start and stop sounds, auto-stop after silence, hiding the menu-bar icon, and history kept for 7 days or forever.

## Calls made in writing this up (the owner can overrule)

- Key choices are Right Command, Right Option, Right Control and Fn (Globe).
- The built-in microphone is preferred with Bluetooth headphones, on by default.
- Music is lowered to 30%, by default, by changing the output volume, not by pausing.
- Sounds are on by default.
- Auto-stop is for hands-free takes only, with a 3-second default.
- History adds 7 days and Forever, plus Clear history.
- Usage stats sit in the History pane and count even when history is off. They are seeded from `dictationCount` and existing history.
- Shortening history asks before deleting existing entries.
- Fn is detected by keycode and flag, and dropped if it proves unreliable.
- With the icon hidden, a fresh launch by the owner opens Settings; a launch at login doesn't.
- All three sounds are kept out of the audio, not just the start sound.

## Left to the builder

The sounds themselves, the VAD choice, how volume changes are faded, the stats layout, and file organisation.

## How we'll know it's done

- Unit tests for the new `SottoCore` logic and the settings migration pass, along with all existing tests.
- Manual checks:
  - each dictation key, including holding, double-tap, a stray tap, a chord and Esc;
  - AirPods connected: dictation uses the Mac's microphone and music in the AirPods stays at full quality;
  - music lowers and comes back on finish, cancel and quit;
  - sounds play and don't appear in the transcript;
  - hands-free stops after 3 seconds of silence, but not during a short pause mid-sentence;
  - hide the icon, then reopen Settings from Spotlight;
  - history set to 7 days and Forever, and an old `historyHours: 24` file migrates;
  - stats count words with history off.
