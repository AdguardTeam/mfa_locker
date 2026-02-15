# Workshop: SDD Spec Prompt

Prompt for the `/sdd-spec` command in Windsurf:

---

Redesign the EntryValueDialog into a full-screen "Entry Reveal" experience with a decryption animation and one-tap copy.

**What it should do:**

When the user taps the view button on an entry and authenticates, instead of the current plain AlertDialog, the app should show a full-screen page (pushed via Navigator, not a dialog) with the following behavior:

1. **Decryption animation** — the entry value appears character by character with a "decrypting" visual effect. Characters start as randomized symbols (like ░▒▓█▄▀╬◆●) and progressively resolve into the real value from left to right over ~1.5 seconds. Think of a Hollywood-style "cracking the code" effect. The animation should use a monospace font for the value display.

2. **Copy to clipboard** — a prominent "Copy" button below the value. On tap it copies the value to the system clipboard and shows a smooth animated transition: the copy icon morphs into a checkmark, the button text changes from "Copy" to "Copied!", and the button color briefly shifts to green. After 2 seconds the button resets to its original state.

3. **Auto-clear clipboard** — after 30 seconds, the app automatically clears the clipboard for security. A subtle circular countdown timer around or near the copy button shows the remaining time. When the timer expires, show a brief "Clipboard cleared" message.

4. **Visual design** — dark background (near-black) for the reveal screen, entry name displayed at the top as a subtitle, the animated value centered with a monospace font (16–18pt), the copy button below it. A simple back arrow or close button in the top-left corner.

**Constraints:**
- Must follow the existing ActionBloc pattern — the new screen is triggered by the existing `showEntryValue` action, so the change is in the UI layer only (no BLoC changes needed).
- Must use standard Flutter animation APIs (AnimationController, Tween) — no external animation packages.
- Must check `context.mounted` before any async UI operations per project conventions.
- The decryption animation should be skippable — tapping on the value text during animation should instantly reveal the full value.
- Must work on all platforms the app supports (iOS, macOS, Android, Windows).
- 120-character line width, trailing commas, single quotes — per project code style.

**Out of scope:**
- Changes to the BLoC layer, repository layer, or core library.
- Changes to the authentication flow.
- Changing how entries are stored or encrypted.
- Adding new dependencies to pubspec.yaml.
