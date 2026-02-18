# Feature Specification: Entry Reveal Screen

**Created**: 2026-02-18
**Status**: Validated
**Input**: File: docs/workshop-sdd-spec-prompt.md

## Assumptions

- **Monospace font**: The system monospace font (`FontFamily.monospace`) is used — no custom font asset is added, keeping the no-new-dependencies constraint.
- **Glyph pool**: Randomized symbols from a fixed set (e.g. `░▒▓█▄▀╬◆●`) are used for the obfuscation effect; the exact set is an implementation detail.
- **Animation timing**: ~1.5 s total reveal duration, left-to-right character resolution. Each character resolves independently.
- **Skip threshold**: A small initial delay (~200 ms) before a tap-to-skip is honoured, to prevent accidental skips on the very first frame.
- **Clipboard clear mechanism**: `Clipboard.setData(ClipboardData(text: ''))` is used to clear; this is the standard cross-platform approach in Flutter.
- **Countdown granularity**: The circular countdown updates every second.
- **"Clipboard cleared" toast**: Shown inline on the screen (not a SnackBar) for 3 s, then disappears — consistent with the dark-screen aesthetic.
- **No BLoC changes**: The trigger is the existing `LockerAction.showEntryValue` action; the UI layer handles the navigation change only.
- **Navigation**: `Navigator.push` via `context.push` (existing extension) replaces the `showDialog` call in `UnlockedScreen`.

## User Scenarios & Testing

### User Story 1 — Decryption Animation Reveal (Priority: P1)

After authenticating to view an entry, the user sees a full-screen dark page where the entry value appears character by character with a "decrypting" visual effect — randomized glyphs resolve left-to-right into the real value over ~1.5 seconds.

**Why this priority**: This is the core feature. Without the animated reveal, the screen has no reason to exist.

**Independent Test**: Navigate to `EntryRevealScreen` with a known value. Verify that immediately after push the displayed text does not equal the real value, and after the animation completes it does.

**Acceptance Scenarios**:

1. **Given** the user has authenticated and the `showEntryValue` action fires, **When** `EntryRevealScreen` is pushed, **Then** the screen shows a dark background, the entry name as a subtitle, and the value area displays randomized glyphs (not the real value).
2. **Given** the reveal animation is running, **When** ~1.5 s elapses, **Then** the full real value is displayed in a monospace font.
3. **Given** the reveal animation is running, **When** the user taps the value text, **Then** the animation skips and the full value is shown immediately.
4. **Given** the screen has just been pushed and the route transition is still animating, **When** the route transition completes, **Then** the reveal animation starts (not before).

---

### User Story 2 — One-Tap Copy with Feedback (Priority: P2)

The user taps a "Copy" button to copy the entry value to the clipboard. The button provides animated feedback: icon morphs to a checkmark, label changes to "Copied!", and the button turns green. After 2 s the button resets.

**Why this priority**: Copying is the primary action on this screen; the animation feedback confirms the action succeeded.

**Independent Test**: Pump `EntryRevealScreen`, wait for animation to complete, tap "Copy", verify button state transitions.

**Acceptance Scenarios**:

1. **Given** the reveal screen is shown, **When** the user taps "Copy", **Then** the entry value is written to the system clipboard, the button icon changes to a checkmark, the label reads "Copied!", and the button color shifts to green.
2. **Given** the button is in "Copied!" state, **When** 2 seconds elapse, **Then** the button resets to the original "Copy" label, copy icon, and blue color.

---

### User Story 3 — Auto-Clear Clipboard with Countdown (Priority: P2)

After copying, a 30-second countdown is shown near the copy button. When it expires the clipboard is cleared automatically and a brief "Clipboard cleared" message is shown.

**Why this priority**: Security requirement — sensitive values must not linger in the clipboard indefinitely.

**Independent Test**: Tap "Copy", verify countdown appears. Advance time by 30 s, verify clipboard is cleared and message shown.

**Acceptance Scenarios**:

1. **Given** the user has tapped "Copy", **When** the clipboard is active, **Then** a circular countdown indicator and "Clipboard clears in Xs" text are visible.
2. **Given** the countdown is running, **When** 30 seconds elapse, **Then** the clipboard is cleared (`Clipboard.setData` with empty string) and a "Clipboard cleared" message appears briefly.
3. **Given** the "Clipboard cleared" message is shown, **When** ~3 seconds elapse, **Then** the message disappears.
4. **Given** the countdown is running, **When** the user taps "Copy" again, **Then** the countdown resets to 30 s.

---

### User Story 4 — Visual Design & Navigation (Priority: P3)

The screen has a near-black background, entry name subtitle, monospace value text, and a back arrow in the top-left corner. It is a full-screen page, not a dialog.

**Why this priority**: Visual polish and navigation correctness. The screen must feel intentional and be dismissible.

**Independent Test**: Push `EntryRevealScreen` from a parent route, verify `AppBar` back button is present and tapping it pops the route.

**Acceptance Scenarios**:

1. **Given** the screen is pushed, **When** it is rendered, **Then** the background is near-black (`#0D0D0D`), the entry name is shown as a small subtitle, and the value uses a monospace font.
2. **Given** the screen is shown, **When** the user taps the back arrow, **Then** the screen is popped and the user returns to the unlocked storage list.

---

### Edge Cases

- What happens when the entry value is empty? → The reveal animation completes instantly (nothing to reveal); the Copy button still works (copies empty string).
- What happens when the user navigates back while the clipboard countdown is running? → The timer is cancelled in `dispose()`; no crash or dangling timer.
- What happens when the user navigates back while the reveal animation is running? → The `AnimationController` is disposed cleanly; no `setState` after unmount.
- What happens if the user taps "Copy" multiple times rapidly? → Each tap resets the 30-second countdown; the button feedback replays from the start.
- What happens on platforms where `Clipboard.setData` is unavailable or throws? → The error is silently swallowed (no user-visible crash); the countdown still runs.

## Requirements

### Functional Requirements

- **FR-001**: The system MUST replace the `EntryValueDialog` with a full-screen `EntryRevealScreen` pushed via `Navigator.push` when the `showEntryValue` action fires.
- **FR-002**: `EntryRevealScreen` MUST display the entry value with a character-by-character reveal animation lasting ~1.5 s using randomized glyph substitution.
- **FR-003**: The reveal animation MUST start only after the route push transition has fully completed (route animation status = `completed`).
- **FR-004**: Tapping the value text during animation MUST skip to the fully revealed state immediately (with a short activation delay to prevent accidental skips).
- **FR-005**: The screen MUST display a "Copy" button that copies the entry value to the system clipboard on tap.
- **FR-006**: On copy, the button MUST animate: icon → checkmark, label → "Copied!", color → green; reverting after 2 s.
- **FR-007**: After copying, the screen MUST display a circular countdown showing seconds remaining until clipboard is cleared (30 s total).
- **FR-008**: After 30 s, the system MUST clear the clipboard and display a "Clipboard cleared" message for ~3 s.
- **FR-009**: The screen MUST use a dark background (`#0D0D0D`), monospace font for the value (16–18 pt), and display the entry name as a subtitle.
- **FR-010**: The screen MUST include an `AppBar` back button that pops the route.
- **FR-011**: All `AnimationController` and `Timer` instances MUST be disposed in `dispose()` to prevent memory leaks.
- **FR-012**: The implementation MUST check `context.mounted` before any `setState` or navigation call following an async operation.
- **FR-013**: No new packages MAY be added to `pubspec.yaml`; only standard Flutter animation APIs are used.
- **FR-014**: The implementation MUST work on iOS, macOS, Android, and Windows.

### Key Entities

- **`EntryRevealScreen`** (`StatefulWidget`): Full-screen widget receiving `entryName` and `entryValue`. Owns all animation controllers, timers, and clipboard state. Lives in `example/lib/features/locker/views/storage/entry_reveal_screen.dart`.
- **`_CopyButton`** (private `StatelessWidget`): Renders the animated copy button driven by an `AnimationController` passed from the parent state.
- **`_ClipboardStatus`** (private `StatelessWidget`): Renders the countdown row or "Clipboard cleared" message based on flags passed from the parent state.

## Success Criteria

- **SC-001**: The reveal animation plays end-to-end without showing the real value until the animation completes (verifiable via widget test: `find.text(realValue)` returns nothing at t=0, finds one widget at t=1.6 s).
- **SC-002**: Tapping the value during animation results in the full value being displayed within one frame (verifiable via widget test).
- **SC-003**: The "Copy" button transitions to "Copied!" state on tap and resets after 2 s (verifiable via widget test with `tester.pump(Duration(seconds: 2))`).
- **SC-004**: The clipboard countdown decrements from 30 to 0 and triggers clipboard clear (verifiable via widget test with fake async timers).
- **SC-005**: `flutter analyze --fatal-warnings --fatal-infos` reports zero issues on all modified and new files.
- **SC-006**: `flutter test` passes all new widget tests for `EntryRevealScreen`.
- **SC-007**: `make dcm-analyze` reports zero issues (file naming, member ordering, BLoC rules).
- **SC-008**: The reveal animation does not start during the Navigator push transition (regression test: at t=50 ms after push, real value is not visible).
