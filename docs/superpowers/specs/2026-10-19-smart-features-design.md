# Sotto: smart features, on-device

Status: approved · 19 October 2026. Not yet implemented.

Project 3 of 4. It comes after accent and slang (`2026-10-19-accent-and-slang-design.md`) and before quality of life (`2026-10-19-quality-of-life-design.md`).

Project 2 is built and merged first. Plan this project against the code as it is after project 2: kept clip records, spelling conversion, the engine interface and learned words already exist.

## Why

The owner wants Sotto to become a free, private, better Wispr Flow, with many features. Wispr Flow's smart features are snippets, styles per app, backtrack ("meet at 2… actually 3" becomes "meet at 3"), numbered lists and command mode (select text, then say what to do with it). Wispr runs these in the cloud. Sotto can run them on the Mac with Apple's on-device language model (the `FoundationModels` framework), which is available on the owner's Mac. It was checked on 19 October 2026: `SystemLanguageModel.default.availability` returned `available`.

The owner dictates mostly into AI coding agents (T3 Code, Codex) and Discord, in casual Australian speech. Chat replies like "yeah" currently come out as "Yeah." because every prose dictation now ends with a full stop, which reads stiffly in Discord.

## Goals

1. **Snippets**: say a short cue and get saved text, such as an email address, a link or a signature.
2. **Apps pane and styles**: per-app choices for mode and writing style, so chats can be casual.
3. **Backtrack**: when the owner corrects themselves mid-dictation, only the corrected version is typed.
4. **Numbered lists**: a dictation spoken as a list becomes a formatted list.
5. **Command mode**: select text in any app, hold a shortcut, say an instruction, and the selection is replaced with the result.
6. **Quiet speech**: dictation still works when the owner speaks softly.

## Non-goals

- Cloud models, or any network request.
- Whole-dictation rewriting or grammar polishing on every take. The language model only runs when a feature needs it.
- Code-editor features such as file tagging and camelCase.
- Translation into other languages.
- Anything in project 4.

## Anti-goals

- **Lag on plain dictation.** A dictation with no list, no backtrack cue and no snippet is not slowed by the language model at all.
- **Made-up words.** The language model adds content the owner didn't say, or drops words they did say, beyond the self-correction it was asked to apply.
- **Dead toggles.** A smart feature looks available when the language model isn't (Apple Intelligence off or the model not ready). Show it as unavailable, with the reason.
- **Lost text.** A command or language-model step fails and the owner's words are lost. On any failure or timeout, insert the plain dictation, and keep it for Copy Last.
- **Literal mode broken.** Styles, backtrack or lists change text typed into terminals or code editors, unless the owner turns that on for the app.
- **Regressions** in typing, the hotkey, smart spacing, learning, or anything from project 2.

## The language model

- Use Apple's `FoundationModels` framework (`SystemLanguageModel`). Check availability at launch and when Apple Intelligence settings change.
- Every call has a short timeout, about 1.5 seconds for dictation steps and 5 seconds for commands. On timeout or error, fall back to the plain text.
- Prompts and the decision of when to call the model are separate from the app code, so they can be tested. The detection logic (cue words, list patterns) lives in `SottoCore` with unit tests. The model call is behind one small interface in the app, so tests can supply a fake.

## Snippets

- A new **Snippets** pane in Settings: a list of snippets, each with a cue phrase and the text to insert. The text can have several lines.
- A snippet fires when the whole dictation, ignoring case, punctuation and filler words, matches its cue. For example, a cue "my email" and a dictation "My email." types the saved address.
- The inserted text is exact: no formatting, spelling conversion, case change or full stop. Only smart spacing's leading space is added.
- Snippets work in every mode.

## Apps pane and styles

A new **Apps** pane lists apps the owner has dictated into (from kept clip records and history), plus an Add button for any app.

**Apps and websites.** A rule belongs to an app, or, in a browser, to a website, using the domain `AppIdentity` already reads (for example `mail.google.com` or `discord.com`). Websites are listed separately from their browser. A website's rule beats its browser's rule.

**Which Mode wins.** The app's or website's own Mode, when it isn't Automatic, wins. Otherwise the Speech pane's Mode applies when it isn't Automatic. Otherwise Sotto uses `AppIdentity`'s guess, as today.

Each app can set:

| Setting | Choices | Default |
|---|---|---|
| Mode | Automatic, Prose, Literal | Automatic |
| Style | Normal, Casual, Very casual | Depends on the app type (below) |
| Smart features | On or off: backtrack and lists for this app | On, except in Literal mode |
| Spelling | Follow the Speech pane, or Off (leave the model's spelling) | Follow the Speech pane |

What each style does to prose text:

- **Normal**: today's behaviour. Capitals, and a full stop at the end.
- **Casual**: capitals, but no full stop at the end of a dictation that is a single sentence. Question and exclamation marks stay.
- **Very casual**: no capital at the start of the dictation and no full stop at the end. "I" stays capital, as do names. Question and exclamation marks stay.

Default styles by app type, using `AppIdentity`: chat apps are **Casual**, everything else is **Normal**. `AppIdentity`'s chat list today has Slack, Discord and Messages. Add WhatsApp, Telegram and Signal, and the web versions of Discord, Slack, WhatsApp and Messenger. The owner can change any app.

A global default style sits in the Speech pane. An app's own setting overrides it.

Smart spacing's sentence rules must follow the style. After a Casual dictation that ended without a full stop, the next dictation into the same field still starts with a capital, because one hold is one sentence. To tell Sotto's own unfinished sentence from text the owner typed, use the record of the last insertion that `TextInserter` already keeps (field, text and time). When the text before the cursor ends with that insertion, treat it as a finished sentence.

## Backtrack

- **Trigger.** Only when the dictation contains a self-correction cue, such as "actually", "I mean", "sorry", "no wait", "scratch that" or "or rather". The cue list lives in `SottoCore`.
- **What it does.** The language model rewrites the dictation with the correction applied and nothing else changed. "Let's meet at 2… actually 3" becomes "Let's meet at 3." "Actually" used normally ("that's actually great") must come back unchanged.
- **Check.** If the result adds words that weren't in the dictation, other than small joining words, discard it and insert the plain text.
- Off in Literal mode unless the app turns smart features on.

## Numbered lists

- **Trigger.** The dictation has at least two items introduced by spoken ordinals or counts in sequence, such as "one… two…" or "first… second… third…". Pattern detection is in `SottoCore`.
- **What it does.** Simple, clear cases are formatted by rules, without the language model: one item per line, as "1. ", "2. " and so on. Unclear cases go to the language model, with the same word-preservation check as backtrack.
- "New line" and "new paragraph" keep working as today.

## Command mode

- **Shortcut.** A second chord in the Shortcut pane, "Command mode", recorded with the existing `KeyboardShortcuts` recorder. It has no default; the owner records one. Until then, the Shortcut pane explains what it does and how to set it.
- **Flow.** The owner selects text in any app, holds the chord, says an instruction such as "make this more formal", "fix the spelling" or "turn this into bullet points", and releases. Sotto reads the selected text through Accessibility, falling back to a borrowed copy as the paste path does, runs the language model with the instruction, and replaces the selection with the result.
- **No selection.** The instruction's result is inserted at the cursor, for requests like "write a polite reply saying I'm running late".
- **Indicator.** It shows a distinct command state while listening and working.
- Never in secure fields. Esc cancels, as it does for dictation. The key listener doesn't swallow Esc, so Esc also reaches the front app. That's accepted, though some apps may clear the selection.
- Terminals are out of scope: they're typed into character by character, which can't replace a selection. In a terminal, command mode shows a short problem message instead.

## Quiet speech

Before transcription, raise the level of quiet takes towards a target loudness, without clipping and without raising background noise in silent takes. The level logic is in `SottoCore` with tests. There's no setting. It's always on.

## Settings summary

| Pane | Rows |
|---|---|
| Snippets (new) | The snippet list, with add, edit and delete. |
| Apps (new) | Per-app mode, style and smart features. |
| Speech | Default style. Backtrack and Numbered lists switches (global, on by default), shown as unavailable when the language model isn't. |
| Shortcut | The Command mode chord. |

## Constraints

- Same platform, signing, project-file and hotkey-path constraints as project 2. No new package dependencies.
- New settings fields decode with defaults when missing, with tests on older `settings.json` files.
- **Portability.** Detection, styles, snippet matching, list formatting by rules, the word-preservation check and loudness logic go in `SottoCore`, which imports only Foundation. Stored snippets and app rules are plain JSON.
- The language-model features must not run on text typed in Literal mode unless the app's setting allows it.

## Decided by the owner

- Sotto should become a free, better, on-device Wispr Flow, with many features.
- These features come after accent and slang and before quality of life.

## Calls made in writing this up (the owner can overrule)

- Apple's on-device language model powers backtrack, unclear lists and command mode.
- Snippets fire on a whole-dictation match of the cue.
- Three styles, Normal, Casual and Very casual, with Casual as the default for chat apps. An earlier draft had Formal, but it behaved the same as Normal, so it was dropped.
- Rules can be set per app and, in a browser, per website.
- An app's Mode beats the Speech pane's Mode, which beats `AppIdentity`'s guess.
- A Casual dictation counts as a finished sentence for the next dictation into the same field.
- WhatsApp, Telegram, Signal and the web chat apps join `AppIdentity`'s chat list.
- Command mode refuses in terminals.
- Command mode uses its own chord with no default, rather than reusing Right Command.
- Quiet-speech boosting is always on, with no setting.
- Backtrack and lists are on by default, and off in Literal mode.

## Left to the builder

Prompt wording, exact cue lists, timeouts within the limits above, the loudness target, the Apps pane layout and how apps are listed, and how the command state looks in the indicator.

## How we'll know it's done

- Unit tests cover detection, styles, snippet matching, list rules, the word-preservation check and loudness, plus decoding of older settings. They pass with all existing tests.
- Manual checks:
  - a snippet cue in T3 Code and Discord;
  - Discord set to Casual: "yeah" types "Yeah" with no full stop; Very casual types "yeah"; a website rule (Gmail in a browser) beats the browser's rule;
  - "let's meet at 2, actually 3" and "that's actually great";
  - a spoken list of three items;
  - command mode on selected text in Notes and in Discord, and with no selection;
  - turn Apple Intelligence off and check the features show as unavailable, and that dictation still works;
  - a whispered dictation;
  - a terminal stays untouched by styles, backtrack and lists.
