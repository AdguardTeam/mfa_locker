# AW-2849 — MFA About Screen

## Summary

Add an About screen to the MFA Demo example app. The screen is accessible
from a new "About" item at the bottom of `SettingsScreen` and displays
basic app information.

## Design References

No Figma designs exist for this ticket. The screen uses standard Material 3
components consistent with the existing app styling.

## Acceptance Criteria

1. `SettingsScreen` has an "About" list item at the bottom of its list.
2. Tapping "About" navigates to `AboutScreen` via `context.push(const AboutScreen())`.
3. `AboutScreen` displays:
   - App icon (the Flutter logo `FlutterLogo` widget or `Image.asset`)
   - App name (from `PackageInfo.appName`)
   - Version string (from `PackageInfo.version` + `PackageInfo.buildNumber`, e.g., "1.0.0 (1)")
   - Copyright notice (static text: "© 2025 AdGuard. All rights reserved.")
   - "View License" link that opens the Flutter `LicensePage`
4. No BLoC is required — the screen loads `PackageInfo` locally (it's pure UI).
5. Zero analyzer warnings; code formatted to 120-char line length.

## Technical Plan

### Files to create
- `example/lib/features/about/views/about_screen.dart` — the `AboutScreen` widget

### Files to modify
- `example/lib/features/settings/views/settings_screen.dart` — add "About" `ListTile` at the bottom of the settings list

### Implementation notes
- Use `PackageInfo.fromPlatform()` in a `FutureBuilder` or load it in `initState` via `setState`.
- Navigation: `context.push(const AboutScreen())` — matches existing push pattern.
- "View License" taps `showLicensePage(context: context)` (built-in Flutter).
- No new dependencies required; `package_info_plus` is already in the pubspec.
- Follow existing code style: single quotes, 120-char lines, `const` constructors, `prefer_expression_function_bodies`.
