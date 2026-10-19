# Sotto: the new look

Status: approved and implemented · 19 October 2026. The plan is `docs/superpowers/plans/2026-10-19-new-look.md`. See "Decisions made during implementation" for where the build refined this design.

This is the first of three projects agreed for Sotto's next round. The other two come later, each with its own design:

1. **The new look** (this document): a customisable listening indicator and a Settings window with a sidebar.
2. **Accent and slang**: a speech model that handles an Australian accent, Australian spelling, and learning from corrections.
3. **More features**: snippets, per-app behaviour, choosing the dictation key, the AirPods microphone fix, lowering music, sounds, auto-stop and longer history.

The new look goes first because every later feature needs a place in Settings.

Update, 19 October 2026: the later work was re-planned as three projects. Each has its own design: accent and slang (`2026-10-19-accent-and-slang-design.md`), smart features on-device (`2026-10-19-smart-features-design.md`), and quality of life (`2026-10-19-quality-of-life-design.md`). Snippets and per-app behaviour moved into smart features.

## Why

Sotto works, but it doesn't feel good to use. While you talk it shows a small text box under the menu bar with the words it thinks it heard. Wispr Flow and ChatGPT show an animated audio indicator instead, and that is what the owner wants: something that visibly reacts to their voice, looks polished, and can be made their own. Its settings are also a single scrolling page. They need room to grow into the many settings projects 2 and 3 will add.

Sotto is the owner's own Wispr Flow. The owner dictates mostly into AI coding agents (T3 Code, Codex, Hermes) and Discord, in casual Australian speech.

## Goals

1. Replace the text box with an animated indicator whose bars follow the real microphone level.
2. Let the owner choose how the indicator looks and where it sits.
3. Replace the Settings page with a Settings window that has a sidebar of categories, like macOS System Settings.
4. Move every existing setting into that window without losing anyone's saved settings.

## Non-goals for this project

These belong to projects 2 and 3, so leave them out here. Don't add placeholder rows for them either:

- a speech model choice, spelling variety, the swearing option, learning from corrections (project 2);
- snippets, per-app rules, choosing a different dictation key, auto-stop after silence, the AirPods microphone fix, lowering music, sounds, hiding the menu-bar icon, history kept for 7 days or forever (project 3).

Also out of scope: searching inside Settings, theming the Settings window itself, and animating the menu-bar icon.

## Anti-goals

Any of these would make the project a failure, even if everything else works:

- **Focus.** The indicator takes keyboard focus or intercepts clicks. Or it covers the line being typed on when Sotto knows where the caret is (see "Staying clear of the caret").
- **Lag.** The bars visibly lag the voice. They should react within about 100 ms.
- **Dead toggles.** A setting appears that does nothing yet.
- **Lost settings.** An existing `settings.json` fails to decode after the upgrade, so the owner's settings reset.
- **Idle cost.** Sotto uses noticeable CPU or redraws while the indicator is hidden.
- **Regressions.** Right Command, the event tap, signing, entitlements or audio capture stop working. All of these were fixed on 19 October 2026.

## The listening indicator

The mockup is in [`2026-10-19-new-look/listening-indicator.html`](2026-10-19-new-look/listening-indicator.html). The owner chose options **A (Pill)** and **B (Notch)** and wants both available as settings. Option C (words above the pill) became the optional "Show words as you talk" setting.

### Styles

- **Pill** (default). A dark capsule with a row of thin vertical bars. The bars are tallest in the middle and move with the voice level.
- **Notch.** A black shape that grows out of the top centre of the screen, like the iPhone's Dynamic Island. It has a small red recording dot on the left and the bars on the right. On a display with a camera notch it wraps around the notch. On a display without one (an external monitor), it draws the same black tab from the top centre of the screen.
- **Dot.** A small round light that pulses with the voice level. It's for people who want the indicator barely there.

### States

The indicator moves through these states. The exact timings, animation curves and transition shapes are up to the builder.

| State | When | What it shows |
|---|---|---|
| Hidden | At rest | Nothing on screen, and no timers or redraws running. |
| Listening | Key held, or hands-free | Bars following the live level. |
| Hands-free | After a double-tap or the menu's Dictate | The same as listening, plus a visible sign that it will keep going until the next press. |
| Working | Key released, before the text lands | Bars settle into a gentle "working" animation. |
| Done | Text inserted | A brief tick, then the indicator leaves. |
| Problem | Text not inserted, or nothing heard | A short plain message for a few seconds. See below. |
| Cancelled | Esc, a stray tap or a chord | Leaves quickly with no message. |

**Problem messages.** These replace today's slip messages. Use friendlier wording for the same cases:

- "not heard" → "Didn't catch that"
- "password refused" → "Won't type into a password field"
- "focus changed" → "You moved away, so it's kept for Copy Last"
- "no focus" → "No text field, so it's kept for Copy Last"
- "could not type" → "Couldn't type here, so it's kept for Copy Last"
- "Turn on Accessibility" → "Turn on Accessibility for Sotto"
- "Turn on Microphone" → "Turn on Microphone for Sotto"
- "model downloading" → "Still downloading the speech model"

The pill and notch widen to fit the message, up to a sensible maximum. With the Dot style, the problem message appears as a small label next to the dot.

### Settings for the indicator

| Setting | Choices | Default |
|---|---|---|
| Style | Pill, Notch, Dot | Pill |
| Position (Pill and Dot only) | Bottom centre, Top centre, At the text cursor | Bottom centre |
| Size | A slider, about 80% to 150% | 100% |
| Bar colour | Six presets: paper (`#F4EFE6`), white, blue, green, pink and orange. Also a custom colour picker. | Paper |
| Background (Pill only) | Dark, Glass (translucent and blurred), Light | Dark |
| Show words as you talk | On or off | Off |
| Show on | The display with the mouse pointer, or the main display | The display with the mouse pointer |

**Which settings apply to which style.** Background only applies to the Pill. The Notch is always black, so it blends with the real notch, and the Dot is just its bar colour. Settings hides Background, and Position, when they don't apply to the chosen style, so no control does nothing.

**At the text cursor.** This places the indicator just below the caret of the focused text field, when Accessibility can report where the caret is. It uses the display the caret is on, whatever "Show on" says. If the caret position isn't available, fall back to Bottom centre on the display "Show on" picks. "Show on" decides the display for Bottom centre, Top centre and the Notch.

**Staying clear of the caret.** Whenever Accessibility reports the caret position, the indicator checks that it won't cover the caret's line, counting any caption or problem message it is showing. If it would, it moves to the opposite edge of the same display (bottom ↔ top) for that take. The Notch moves out of the way by dropping its caption below the caret line. When the caret position isn't known, the indicator stays where the owner put it. It is transient and lets clicks through, so a brief overlap there is acceptable.

**Show words as you talk.** When this is on, Apple's provisional words (from `LiveLine`, which already exists) appear in a small caption: above the pill, under the notch, or next to the dot.

**Reduce Motion.** When macOS's Reduce Motion is on, keep the level visible but drop the bouncing. For example, bars could change opacity instead of height. The builder picks the treatment.

### Behaviour that must carry over from today's slip

- It never takes focus or receives clicks.
- It shows on every Space and over full-screen apps.
- It never activates Sotto.

## The Settings window

The mockup is in [`2026-10-19-new-look/settings-window.html`](2026-10-19-new-look/settings-window.html). The owner approved the layout. It's a standard macOS window with a sidebar of categories on the left and the selected category's settings on the right, grouped the way System Settings groups them. The window follows the system's light or dark appearance. It opens on the category that was showing last time.

**How it opens.** From the menu bar's "Settings…" item, and with ⌘, while the window is in front. Opening Sotto again from Finder or Spotlight should also open it. It must come to the front even though Sotto is a menu-bar app with no Dock icon.

### Categories and what moves where

These are only the settings that work today, plus this project's additions:

| Category | Contents |
|---|---|
| General | Open Sotto at login (**new**, using the system login-item API). |
| Shortcut | How the dictation key works: hold Right Command, double-tap to keep listening, Esc to cancel. The chord recorder. If Accessibility is off, a notice and a button to fix it. |
| Indicator | Everything in "Settings for the indicator", with a **live preview** at the top that reflects each change as it's made, as in the mockup. |
| Microphone | Input device picker. "Keep the first syllable", with its explanation. A live input level meter (**new**). |
| Speech | Mode (Automatic, Prose, Literal). Speech model status, with Retry when it failed. Language, shown as English for now. |
| Dictionary | Today's Names list (heard → written), with add and remove. |
| History | Off or 24 hours, as today. A list of recent entries with a Copy button each (**new**). |
| Privacy & Permissions | Live status of Microphone and Accessibility, each with a button that fixes it when off. The privacy statement: audio is never saved, and nothing leaves the Mac except the model download. |
| About | Version, and the speech model credit. That credit is required by the model's CC-BY-4.0 licence. |

Projects 2 and 3 will add categories (such as Snippets and Apps) and rows. Leave room for that, but don't show empty categories now.

## Constraints

- macOS 26 or later, Swift 6 language mode with complete concurrency checking, SwiftUI plus AppKit, as the app is today. Don't add new package dependencies.
- `project.yml` is the source of truth for the Xcode project. Regenerate with XcodeGen, and don't change the signing identity, team or entitlements.
- **Settings migration.** `AppSettings` is decoded with synthesised `Codable`, which fails when the file lacks a key. New fields must decode with defaults when they're missing (`decodeIfPresent` or equivalent). Add a unit test that decodes today's `settings.json` shape.
- **Input level.** `AudioCapture` must publish a smoothed input level for the indicator and the meter. Compute it on the audio queue, and keep it cheap. It is only needed while the indicator or the meter is visible.
- Logic that doesn't need AppKit belongs in `SottoCore` with unit tests. That includes level smoothing, the indicator's state transitions, mapping failures to messages, and position maths.
- Today's `SlipPanel` is replaced, not kept alongside.

## Decided by the owner

- An animated indicator replaces the text box.
- Both the Pill and the Notch styles are offered and are customisable.
- Settings becomes a window with a sidebar of categories, laid out as in the mockup.
- The owner wants all the settings marked "new" in the mockup. They are split across the three projects above, in that order.

## Calls made in writing this up (the owner can overrule)

- Pill at bottom centre is the default style. Words-as-you-talk is off by default.
- The Dot style, the Glass and Light backgrounds, and the "Show on" display choice are extras beyond A and B.
- On displays without a notch, the Notch style draws its own black tab.
- Problem messages use the friendlier wording above.
- Settings has no search. With nine categories it isn't needed yet.
- History's list and the microphone level meter come in this project, because they're display-only. Longer history options wait for project 3.
- Background applies only to the Pill. The Notch stays black and the Dot is its bar colour. Inapplicable rows are hidden.
- "At the text cursor" follows the caret's display. "Show on" governs every other position.
- When the caret position is known and the indicator would cover its line, the indicator jumps to the opposite edge for that take. When it isn't known, it stays where the owner put it.
- Open at login is the only new General setting in this project.

## Decisions made during implementation

The build refined this design in these places. Each was a ruling made on the owner's behalf. The owner can overrule any of them.

- **Caption side at the text cursor.** At the text cursor, the caption goes on the side of the indicator away from the caret, so it never lands on the line being typed.
- **Staying on screen wins.** Widths are capped to the display, and every part of the indicator is kept on screen. When staying on screen and staying clear of the caret can't both hold, staying on screen wins.
- **Notch fallback.** If the Notch tab itself would cover the caret's line (for example, a full-screen editor on a display without a notch), that take shows the Pill at bottom centre instead. Saved settings don't change.
- **Esc while working.** Esc also cancels a take that is still Working after the key is released: nothing is inserted and nothing is shown.
- **Overlapping takes.** If a new take starts before the previous one finishes, the previous take's text still inserts, but only the newest take is shown in the indicator. Stale results never replace newer messages.
- **Meter lifetime.** The level meter runs only while the Settings window is visible and the Microphone page is selected.
- **Dock icon.** Sotto shows a Dock icon while Settings is open, because an accessory app doesn't reliably bring its window to the front otherwise.
- **Narrow displays.** On displays narrower than about 436 pt, which no Mac has, the indicator's drawing isn't shrunk to fit.

## Left to the builder

Within the anti-goals above, these are the builder's choice: exact animation timings and curves, bar count and spacing, preset colour values other than paper, whether the indicator is drawn in SwiftUI or AppKit, how its window is managed, how the caret position is read, and how files are organised.

## How we'll know it's done

- Unit tests cover the new `SottoCore` logic, including decoding an old `settings.json`, and pass.
- The app builds and the existing 32 tests still pass.
- Manual checks:
  - each style and position, on a display with a notch and on one without;
  - light and dark appearance;
  - Reduce Motion on;
  - a full-screen app, and another Space;
  - each problem message;
  - settings surviving a relaunch;
  - Right Command still dictating into T3 Code and Discord;
  - CPU near zero while idle.
