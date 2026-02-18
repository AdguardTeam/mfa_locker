# Implementation Plan: Entry Reveal Screen

**Input**: Feature specification from `/specs/.current/spec.md`
**User Input**: None

## Summary

Replace the `EntryValueDialog` (plain `AlertDialog`) with a full-screen `EntryRevealScreen` pushed via `Navigator.push`. The new screen shows the entry value with a character-by-character "decryption" animation (~1.5 s), a one-tap copy button with animated feedback, and a 30-second auto-clear clipboard countdown. The change is **UI-layer only** — no BLoC, repository, or library changes are needed. The trigger is the existing `LockerAction.showEntryValue` action handled in `UnlockedScreen`.

## Technical Context

| Field | Value |
|-------|-------|
| **Language** | Dart >=3.9.0 (example app) |
| **Flutter** | 3.35.1 (FVM locked) |
| **Architecture** | UI layer only — triggered by `LockerAction.showEntryValue` |
| **State Management** | `StatefulWidget` + `AnimationController` + `Timer` (no BLoC changes) |
| **Animation APIs** | `AnimationController`, `AnimationBehavior.preserve`, `ModalRoute.of(context)?.animation` |
| **Clipboard** | `flutter/services.dart` → `Clipboard.setData` / `ClipboardData` |
| **Testing** | `flutter_test`, `mocktail` not needed (pure widget test), `SystemChannels.platform` mock for clipboard |
| **Platforms** | iOS, macOS, Android, Windows |
| **Line width** | 120 chars, trailing commas, single quotes |

## Research Findings

### Existing Action/Navigation Flow

- `LockerAction.showEntryValue({name, value})` is dispatched by `LockerBloc` in two handlers: `_onViewEntryRequested` and `_onReadEntryWithBiometricRequested`.
- `UnlockedScreen` listens via `BlocActionListener` and currently calls `showDialog<void>` with `EntryValueDialog`.
- The change: replace `showDialog` with `context.push(EntryRevealScreen(...))` using the existing `NavigatorExtension.push` in `context_extensions.dart`.

### Route-Aware Animation Start

- `ModalRoute.of(context)?.animation` provides the route push animation.
- Subscribe to its `AnimationStatus` in `didChangeDependencies`. Start reveal only when status is `AnimationStatus.completed`.
- Guard with `addPostFrameCallback` to defer `forward(from: 0.0)` by one frame, ensuring the first fully-obfuscated frame renders before animation begins.
- Use `AnimationBehavior.preserve` on the reveal controller so it is not suppressed by `MediaQuery.disableAnimations`.

### Tap-to-Skip Guard

- Tapping immediately (< 8% progress) should not skip — user may tap accidentally on the first frame.
- Use a `Timer` of ~220 ms: if the tap fires before 8% progress, schedule the skip after the delay. If progress ≥ 8%, skip immediately.

### Clipboard Handling

- `Clipboard.setData(ClipboardData(text: ''))` clears clipboard cross-platform.
- In tests, mock `SystemChannels.platform` to intercept clipboard method calls.
- `unawaited_futures` lint: use `unawaited()` from `dart:async` for fire-and-forget futures inside sync callbacks, or make the callback `async`.

### Private Widget Extraction

- Per `conventions.md`: extract `_CopyButton` and `_ClipboardStatus` as private `StatelessWidget` classes (not helper methods returning `Widget`).
- Per DCM `prefer-match-file-name`: all private classes live in the same file as `EntryRevealScreen` — this is acceptable since they are private (`_` prefix) and the file is named after the primary public type.

### Import Ordering

- `dart:` imports first, then `package:flutter/`, then `package:mfa_demo/`, then relative — run `dart fix --apply` or sort manually to satisfy `directives_ordering`.

### `unawaited_futures` in Timer Callbacks

- `_clearClipboard()` is called from a `Timer.periodic` callback (sync). Must either `await` it (not possible in sync callback) or wrap with `unawaited(...)`.
- Similarly `_copyController.reverse()` returns a `TickerFuture` — wrap with `unawaited` or ignore via `// ignore` (prefer `unawaited`).

## Entities

### New: `EntryRevealScreen` (StatefulWidget)

**File**: `example/lib/features/locker/views/storage/entry_reveal_screen.dart`

```
EntryRevealScreen
  final String entryName
  final String entryValue
  State → _EntryRevealScreenState
    AnimationController _revealController   (1.5 s, AnimationBehavior.preserve)
    AnimationController _copyController     (300 ms, for button color/icon)
    Timer? _clipboardTimer                  (periodic, 1 s interval)
    Timer? _skipActivationTimer             (one-shot, 220 ms)
    bool _copied
    bool _clipboardActive
    bool _clipboardCleared
    int _clipboardSecondsLeft               (30 → 0)
```

### New: `_CopyButton` (private StatelessWidget, same file)

Receives `AnimationController controller`, `bool copied`, `VoidCallback onPressed`. Renders `FilledButton.icon` with `AnimatedSwitcher` for icon/label and `Color.lerp` for background.

### New: `_ClipboardStatus` (private StatelessWidget, same file)

Receives `bool active`, `bool cleared`, `int secondsLeft`. Renders countdown row or "Clipboard cleared" text or `SizedBox.shrink()`.

### Modified: `UnlockedScreen`

**File**: `example/lib/features/locker/views/storage/unlocked_screen.dart`

- Replace `showDialog` + `EntryValueDialog` import with `context.push(EntryRevealScreen(...))` + `entry_reveal_screen.dart` import.
- Fix import ordering (`directives_ordering` lint).

## Project Structure Changes

```
example/lib/features/locker/views/storage/
  entry_reveal_screen.dart          ← NEW (EntryRevealScreen, _CopyButton, _ClipboardStatus)
  unlocked_screen.dart              ← MODIFIED (action handler + import)

example/test/features/locker/views/storage/
  entry_reveal_screen_test.dart     ← NEW (widget tests)
```

No new directories needed. No Freezed models. No `make gen` required.

## Tasks

### Phase 1 — Core Widget

#### P1-T1: Create `EntryRevealScreen` with decryption animation [M] ✅

**File**: `example/lib/features/locker/views/storage/entry_reveal_screen.dart`

Implement `EntryRevealScreen` as a `StatefulWidget` with:
- `_revealController` (`AnimationController`, 1.5 s, `AnimationBehavior.preserve`)
- `_buildDisplayValue(double progress)` — returns string where chars `< revealedCount` are real, rest are random glyphs from a fixed pool
- `didChangeDependencies` subscribes to `ModalRoute.of(context)?.animation` status
- `_startRevealIfNeeded()` — checks route animation is `completed` (or null), then `addPostFrameCallback` → `_revealController.forward(from: 0.0)`
- `_onRevealValueTapped()` — skip logic with 220 ms activation delay for < 8% progress
- `dispose()` cancels all controllers and timers
- `AppBar` with `foregroundColor: Colors.white`, dark `backgroundColor`
- Entry name subtitle, `AnimatedBuilder` on `_revealController` for value text with monospace font

**Verification**:
- [ ] `flutter analyze --fatal-warnings --fatal-infos` → zero issues
- [ ] File compiles without errors

---

#### P1-T2: Add copy button and clipboard countdown [M] ✅

**File**: `example/lib/features/locker/views/storage/entry_reveal_screen.dart`

Add to `_EntryRevealScreenState`:
- `_copyController` (`AnimationController`, 300 ms)
- `_onCopyPressed()` — `async`, calls `Clipboard.setData`, sets `_copied = true`, starts `_copyController.forward`, starts `_clipboardTimer` (periodic 1 s), after `_copyResetDelay` resets `_copied` and calls `unawaited(_copyController.reverse())`
- `_clearClipboard()` — `async`, calls `Clipboard.setData(ClipboardData(text: ''))`, sets `_clipboardActive = false`, `_clipboardCleared = true`, after 3 s sets `_clipboardCleared = false`
- `_clipboardTimer` callback: decrements `_clipboardSecondsLeft`, calls `unawaited(_clearClipboard())` at 0

Add private widgets:
- `_CopyButton`: `AnimatedBuilder` on controller, `Color.lerp` blue→green, `AnimatedSwitcher` for icon (copy→check) and label (Copy→Copied!)
- `_ClipboardStatus`: conditional render of countdown row or "Clipboard cleared" text

**Verification**:
- [ ] `flutter analyze --fatal-warnings --fatal-infos` → zero issues
- [ ] No `unawaited_futures` warnings

---

### Phase 2 — Integration

#### P2-T1: Update `UnlockedScreen` to push `EntryRevealScreen` [S] ✅

**File**: `example/lib/features/locker/views/storage/unlocked_screen.dart`

- Replace `import 'package:mfa_demo/features/locker/views/widgets/entry_value_dialog.dart'` with `import 'package:mfa_demo/features/locker/views/storage/entry_reveal_screen.dart'`
- Fix import ordering to satisfy `directives_ordering` (storage imports before widgets imports, both are `package:mfa_demo/` — sort alphabetically)
- Replace `showDialog<void>(context: context, builder: (context) => EntryValueDialog(...))` with `context.push(EntryRevealScreen(entryName: value.name, entryValue: value.value))`

**Verification**:
- [ ] `flutter analyze --fatal-warnings --fatal-infos` → zero issues on `unlocked_screen.dart`

---

### Phase 3 — Tests

#### P3-T1: Write widget tests for `EntryRevealScreen` [M] ✅

**File**: `example/test/features/locker/views/storage/entry_reveal_screen_test.dart`

Test cases (Arrange/Act/Assert):

1. **Shows entry name as subtitle** — pump screen, `find.text('My Secret')` finds one widget.
2. **Value is obfuscated before animation completes** — pump screen + `pump()`, `find.text(realValue)` finds nothing.
3. **Value is revealed after animation completes** — pump screen, `pump(Duration(milliseconds: 1600))`, `find.text(realValue)` finds one widget.
4. **Copy button is present** — `find.text('Copy')` and `find.byIcon(Icons.copy)` find widgets.
5. **Tap-to-skip reveals value** — pump, advance 300 ms, tap `GestureDetector`, advance 300 ms, `find.text(realValue)` finds one widget.
6. **Copy button shows "Copied!" after tap** — mock `SystemChannels.platform`, tap Copy, pump, `find.text('Copied!')` finds one widget.
7. **Copy button resets after 2 s** — tap Copy, pump 2 s, `find.text('Copy')` finds one widget.
8. **Clipboard countdown appears after copy** — tap Copy, pump, `find.textContaining('Clipboard clears in')` finds one widget.
9. **Back button present when pushed via Navigator** — push screen from parent route, `pumpAndSettle`, `find.byType(BackButton)` finds one widget.
10. **Reveal does not start during route transition** — push via `Navigator.push`, pump + pump 50 ms, `find.text(realValue)` finds nothing.

**Verification**:
- [ ] `fvm flutter test example/test/features/locker/views/storage/entry_reveal_screen_test.dart` → all pass

---

### Phase 4 — Final Verification

#### P4-T1: Full project verification [S] ✅

- [ ] `fvm flutter analyze --fatal-warnings --fatal-infos` (from `example/`) → zero issues
- [ ] `fvm flutter test` (from root) → all tests pass
- [ ] `fvm dart format . --line-length 120` (from `example/`) → no changes needed
- [ ] `make dcm-analyze` → zero issues

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `unawaited_futures` lint on `Timer` callbacks | Wrap fire-and-forget async calls with `unawaited()` from `dart:async` |
| `directives_ordering` lint in `unlocked_screen.dart` | Sort imports alphabetically after edit |
| Reveal starts during route transition | Subscribe to `ModalRoute.of(context)?.animation` in `didChangeDependencies`; guard with `AnimationStatus.completed` check |
| `setState` after `dispose` | Check `mounted` before every `setState` in async callbacks and timer callbacks |
| DCM `prefer-match-file-name` for private classes | Private classes (`_CopyButton`, `_ClipboardStatus`) are exempt — only public types must match file name |
| `avoid_redundant_argument_values` | Remove any default-value arguments (e.g. `rootNavigator: false`) |
