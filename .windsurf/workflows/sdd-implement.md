---
description: Implement a feature according to its specification and plan (v1.5.0)
auto_execution_mode: 2
---

# Implement Feature

This workflow implements a feature by executing the tasks defined in the
implementation plan (`/specs/.current/plan.md`) according to the feature
specification (`/specs/.current/spec.md`).

## Input

The workflow accepts optional user input (`$ARGUMENTS`) to control implementation
scope. Examples:

- Task selection: "Task 1.1 only" or "Phase 1"
- Resume point: "Continue from Task 2.3"
- Skip tasks: "Skip tests for now"

If no arguments are provided, the workflow implements all tasks in order.

## Prerequisites

Check for the existence of both required files:

1. `/specs/.current/spec.md` - The feature specification
2. `/specs/.current/plan.md` - The implementation plan

If either file is missing:

**ERROR: Required files not found. Ensure both `/specs/.current/spec.md` and
`/specs/.current/plan.md` exist. Run `/sdd-spec` and `/sdd-plan` first.**

## Steps

### Phase 1: Load Context

1. **Read the implementation plan**
   - Read `/specs/.current/plan.md`
   - Extract all tasks with their:
     - Description and complexity
     - Prerequisites
     - Verification criteria
   - Note the task execution order

2. **Read the feature specification**
   - Read `/specs/.current/spec.md`
   - Extract functional requirements for reference
   - Note acceptance scenarios for verification

3. **Read project conventions and guidelines**
   - Read `docs/conventions.md` for coding standards, naming conventions, file
     organization, class member order, and BLoC patterns
   - Read `docs/workflow.md` for iteration process
     (PROPOSE -> IMPLEMENT -> TEST -> UPDATE -> CONFIRM)
   - Read `docs/guidelines.md` for Flutter/Dart best practices (null safety,
     async patterns, widget composition)
   - These inform implementation style and conventions

### Phase 2: Determine Scope

1. **Parse user input** (if provided)
   - Identify which tasks to implement
   - Note any tasks to skip
   - Determine starting point

2. **Build task queue**
   - If no input: queue all tasks in plan order
   - If input specifies tasks: queue only those tasks
   - Verify prerequisites are satisfied for queued tasks

3. **Report scope**
   - List tasks that will be implemented
   - Note any skipped tasks and reasons
   - Confirm with user if scope is ambiguous

### Phase 3: Execute Tasks

For each task in the queue:

1. **Announce task**
   - Display task ID, description, and complexity
   - List prerequisites and their status

2. **Research before coding**
   - Search codebase for related patterns
   - Find similar implementations to follow
   - Identify files that need modification

3. **Implement the task**
   Follow these Dart/Flutter conventions:

   **Code style (from `docs/conventions.md`):**
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

   **Class member order:**
   1. Static constants (public, then private)
   2. Constructor fields (public, then private)
   3. Constructor
   4. Other private fields
   5. Public methods
   6. Private methods

   **Widget lifecycle order:**
   `initState` -> `didUpdateWidget` -> `didChangeDependencies` -> `build` ->
   `dispose` -> custom methods

   **Patterns:**
   - Run `make gen` after creating/modifying Freezed models
   - Check `context.mounted` before navigation/dialogs after async operations
   - Let exceptions propagate -- don't wrap `StorageException`,
     `BiometricException`, `DecryptFailedException` in custom exceptions
   - Exact dependency versions (no `^` caret), alphabetical order
   - Prefer minimal, focused changes
   - Create new files only when necessary

4. **Verify the task**
   - Execute the verification criteria from the plan
   - Run relevant tests if they exist
   - Check that acceptance scenarios pass
   - Run: `fvm flutter analyze --fatal-warnings --fatal-infos`
   - Run: `fvm flutter test`
   - Run: `fvm dart format . --line-length 120`

5. **Report task status**
   - **DONE**: Task completed and verified
   - **BLOCKED**: Cannot proceed (explain why)
   - **NEEDS INPUT**: Requires user decision

6. **Update plan progress**
   - Mark completed tasks in the plan file
   - Add implementation notes if helpful

### Phase 4: Integration Check

After completing all queued tasks:

1. **Run project verification**
   - `fvm flutter analyze --fatal-warnings --fatal-infos` (static analysis)
   - `fvm flutter test` (test suite)
   - `fvm dart format . --line-length 120` (formatting)
   - `make dcm-analyze` (Dart Code Metrics, for example app)

2. **Check requirement coverage**
   - For each functional requirement in the spec
   - Verify implementation addresses it
   - Note any gaps

3. **Report completion status**
   - List completed tasks
   - List any remaining tasks
   - Note issues encountered

4. **Update spec status**
   - If all tasks completed successfully:
     - Change status from "Draft" to "Implemented" in `spec.md`
     - Add implementation notes if helpful

## Task Execution Guidelines

### Code Quality

- **Follow existing patterns**: Match the style of surrounding code and
  `docs/conventions.md`
- **Minimal changes**: Implement only what the task requires
- **No premature optimization**: Focus on correctness first
- **Document decisions**: Add comments for non-obvious choices
- **Class member order**: Static constants -> constructor fields -> constructor ->
  private fields -> public methods -> private methods
- **Widget lifecycle**: `initState` -> `didUpdateWidget` ->
  `didChangeDependencies` -> `build` -> `dispose` -> custom methods

### Testing

- **Write tests alongside code**: Don't defer testing
- **Use `mocktail`**: Mocks in `test/mocks/`, named `Mock` + class (e.g.,
  `MockEncryptedStorage`)
- **`registerFallbackValue()`** in `setUpAll` for mocktail value matchers
- **Arrange/Act/Assert**: Follow this structure in all tests
- **Test helpers as `part` files**: e.g., `mfa_locker_test_helpers.dart` is
  `part` of the test file
- **`tearDown` disposes SUT**: Always clean up the system under test
- **Cover acceptance scenarios**: Each scenario should have a test
- **Test edge cases**: Include boundary conditions from the spec

### Error Handling

- **Task blocked**: Stop and report the blocker clearly
- **Ambiguous requirement**: Make a reasonable choice and document it
- **Test failure**: Fix the issue before proceeding
- **Build failure**: Resolve before moving to next task

### Progress Tracking

- **One task at a time**: Complete and verify before moving on
- **Update plan file**: Mark tasks as complete with `[x]`
- **Note deviations**: Document any changes from the plan

## Output

After implementation:

1. **Summary of completed work**
   - Tasks completed
   - Files created/modified
   - Tests added

2. **Remaining work** (if any)
   - Tasks not yet implemented
   - Known issues or blockers

3. **Next steps**
   - Suggest running `/sdd-validate` to verify completeness
   - Note any manual verification needed

## Guidelines

- **Incremental progress**: Complete tasks one at a time
- **Verify continuously**: Don't accumulate unverified changes
- **Respect prerequisites**: Don't skip task dependencies
- **Stay in scope**: Implement what the plan specifies, no more
- **Document blockers**: If stuck, explain clearly and stop
- **Follow project conventions**: Adhere to `docs/conventions.md` and
  `docs/vision.md` guidelines
- **MCP tools preferred**: Use `mcp__dart__analyze_files` over shell `flutter
  analyze`, `mcp__dart__run_tests` over shell `flutter test`,
  `mcp__dart__dart_format` over shell `dart format`
