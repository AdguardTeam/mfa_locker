---
description: Implement a fix or small change from a quick specification (v1.5.0)
auto_execution_mode: 2
---

# Quick Implementation

This workflow implements a fix or small change according to the analysis in
the quick specification (`/specs/.current/quick.md`).

## Prerequisites

Check for the existence of the required file:

- `/specs/.current/quick.md` - The quick specification

If the file is missing:

**ERROR: Quick spec not found. Run `/sdd-quickspec` first to analyze the problem.**

## Steps

### Phase 1: Load Context

1. **Read the quick spec**
    - Read `/specs/.current/quick.md`
    - Extract:
        - Problem statement
        - Root cause analysis
        - Affected files list
        - Proposed solution
        - Verification steps

2. **Read project conventions**
    - Read `docs/conventions.md` for coding standards, naming conventions, file
      organization rules, and BLoC patterns
    - Read `docs/workflow.md` for iteration process
      (PROPOSE -> IMPLEMENT -> TEST -> UPDATE -> CONFIRM)

3. **Verify affected files exist**
    - Check that all files listed in the quick spec exist
    - If files are missing, report and stop

### Phase 2: Implement

1. **Apply the fix or change**
    - Follow the solution approach from the quick spec
    - Modify files in the order listed
    - Follow existing code patterns and these Dart/Flutter conventions:

    **Code style:**
    - Trailing commas on multi-line calls
    - Curly braces for all control flow (no single-line `if (!mounted) return;`)
    - Arrow syntax for one-liners
    - `const` where possible
    - Single quotes for strings
    - 120 character line width

    **File organization:**
    - One primary type per file, file name must match class name
    - Extensions in separate files, named after the extension
    - Sealed classes separate from widgets

    **Naming:**
    - Interfaces: no prefix (`LockerRepository`)
    - Implementations: `Impl` suffix (`LockerRepositoryImpl`)
    - BLoC events: past tense (`UnlockRequested`, `EntryAdded`)
    - BLoC actions: descriptive (`ShowErrorAction`)
    - Private fields/methods: `_` prefix

    **Patterns:**
    - Check `context.mounted` before navigation/dialogs after async operations
    - Let exceptions propagate -- don't wrap `StorageException`,
      `BiometricException`, `DecryptFailedException`
    - Exact dependency versions (no `^` caret), alphabetical order
    - Keep changes minimal and focused

2. **Run code generation if needed**
    - If Freezed models were created or modified, run `make gen`

3. **Update tests** (if applicable)
    - Add or update tests to cover the change
    - Use `mocktail` for mocking (mocks in `test/mocks/`, named `Mock` + class)
    - Follow Arrange/Act/Assert pattern
    - Use `registerFallbackValue()` in `setUpAll` for mocktail value matchers
    - Ensure tests verify the fix works

4. **Update documentation** (if applicable)
    - Update any affected documentation
    - Add comments for non-obvious changes

### Phase 3: Verify

1. **Run verification steps**
    - Execute each verification item from the quick spec
    - Run relevant tests
    - Perform any manual checks listed

2. **Run project checks**
    - `fvm flutter analyze --fatal-warnings --fatal-infos` (static analysis)
    - `fvm flutter test` (test suite)
    - `fvm dart format . --line-length 120` (formatting)

3. **Confirm fix**
    - Verify the original problem is resolved
    - Check for regressions

### Phase 4: Cleanup

1. **Update quick spec status**
    - Change status from "Draft" to "Implemented" in `quick.md`
    - Add implementation notes if helpful

2. **Update CHANGELOG** (if applicable)
    - Add entry to the Unreleased section
    - Use appropriate subsection (Fixed, Changed, etc.)

3. **Final verification**
    - `fvm flutter analyze --fatal-warnings --fatal-infos`
    - Run `make gen` if Freezed models were modified
    - Fix any remaining issues

## Output

After implementation:

1. **Summary**
    - What was fixed or changed
    - Files modified
    - Tests added or updated

2. **Verification results**
    - Which checks passed
    - Any issues encountered

3. **Next steps** (if any)
    - Additional manual verification needed
    - Related issues to address

## Guidelines

- **Follow the spec**: Implement what the quick spec describes
- **Minimal changes**: Don't expand scope beyond the spec
- **Verify before completing**: Ensure the fix actually works
- **Update tests**: Cover the change with tests when possible
- **Document changes**: Update CHANGELOG for user-visible changes
- **Stay focused**: If new issues are discovered, create separate tasks
- **Follow conventions**: Adhere to `docs/conventions.md` standards
- **MCP tools preferred**: Use `mcp__dart__analyze_files` over shell `flutter
  analyze`, `mcp__dart__run_tests` over shell `flutter test`,
  `mcp__dart__dart_format` over shell `dart format`
