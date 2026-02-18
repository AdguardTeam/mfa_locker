---
description: Create an implementation plan from a feature specification (v1.5.0)
auto_execution_mode: 2
---

# Create Implementation Plan

This workflow generates a structured implementation plan from a feature
specification created by `/sdd-spec`. The plan includes technical context,
research findings, entity definitions, Dart interfaces, and actionable tasks.

## Input

The workflow accepts optional user input (`$ARGUMENTS`) to provide additional
context or constraints for the implementation plan. Examples:

- Scope constraints: "Focus on the library layer only"
- Priority guidance: "Prioritize performance over simplicity"
- Clarifications: Answers to questions marked in the spec

If no arguments are provided, the workflow proceeds using only the feature spec
and codebase analysis.

## Prerequisites

Check for the existence of `/specs/.current/spec.md`. If it does not exist:

**ERROR: Feature specification not found at `/specs/.current/spec.md`. Please
run `/sdd-spec` first to create a feature specification.**

## Steps

### Phase 1: Context Gathering

1. **Read the feature specification**
   - Read `/specs/.current/spec.md`
   - Extract the feature name, requirements, user scenarios, and success criteria
   - Note any clarifications marked in the spec

2. **Process user input** (if provided)
   - Parse `$ARGUMENTS` for constraints or clarifications
   - Use user input to resolve "NEEDS CLARIFICATION" items from the spec
   - Note any constraints that affect technical decisions

3. **Read the project documentation**
   - Read `docs/vision.md` for architecture principles, layer responsibilities,
     and anti-patterns to avoid
   - Read `docs/conventions.md` for coding standards, naming conventions, file
     organization rules, and BLoC patterns
   - Read `docs/guidelines.md` for Flutter/Dart best practices (null safety,
     async patterns, widget composition, testing)
   - Scan existing source directories to understand current structure

4. **Apply Technical Context**
   The following technical context is known for this project:

   - **Language/Version**: Dart (SDK >=3.5.0), Flutter (>=3.35.0)
   - **FVM**: Flutter 3.35.1 locked in `.ci-flutter-version`
   - **Primary Dependencies**: `flutter_bloc` + `action_bloc` (local package) +
     `freezed` for state management; `mocktail` for testing
   - **Architecture**: UI -> BLoC (ActionBloc) -> Repository -> MFALocker Library
   - **Testing**: `mocktail` for mocking, Arrange/Act/Assert pattern
   - **Target Platforms**: iOS, macOS, Android, Windows
   - **Project Type**: Two-project structure -- root = `locker` library (Dart
     package), `example/` = `mfa_demo` Flutter app (separate pubspec)
   - **Platform Plugins**: `packages/biometric_cipher/` (platform channel for
     TPM/Secure Enclave), `packages/secure_mnemonic/` (mnemonic key storage)

### Phase 2: Research

1. **Research unknowns**
   For any aspects not covered by the known technical context:
   - Search the codebase for related patterns
   - Read `docs/guidelines.md` for Flutter/Dart best practices
   - Check existing BLoC/repository patterns in the codebase
   - Document findings with sources

2. **Research technology choices**
   For each technology in the stack:
   - Find best practices for that technology in the feature's domain
   - Identify common patterns and anti-patterns (consult `docs/vision.md`)
   - Note any version-specific considerations

3. **Consolidate findings**
   - Summarize research in the Research section
   - Link to relevant documentation or resources
   - Highlight decisions that need user input

### Phase 3: Entity Extraction

1. **Extract entities from the feature spec**
   For each entity identified, use Dart/Flutter-specific modeling:

   **Freezed models** (immutable data classes):
   - **Name**: Class identifier (PascalCase, matching file name)
   - **Fields**: Attributes with Dart types, `@Default` values, `@JsonKey`
     annotations where needed
   - **Relationships**: Composition with other models (not inheritance)
   - **Validation rules**: Dart type system + Freezed assertions
   - **State transitions**: Lifecycle states (if applicable)

   **BLoC components** (state management):
   - **Events**: Past tense naming (`UnlockRequested`, `EntryAdded`)
   - **States**: Data classes holding UI state
   - **Actions**: Descriptive side effects (`ShowErrorAction`,
     `BiometricAuthenticationCancelledAction`)

   **Repository interfaces**:
   - **Abstract class**: No prefix (`LockerRepository`)
   - **Implementation**: `Impl` suffix (`LockerRepositoryImpl`)
   - **Method signatures**: Return types, parameters, callback typedefs

2. **Map to existing entities**
   - Check if entities already exist in the codebase
   - Identify modifications needed to existing Freezed models or BLoC components
   - Note new entities to be created

### Phase 4: Interfaces & Contracts

1. **Define Dart interfaces for the feature**
   For each component that exposes functionality:
   - Define abstract classes with method signatures
   - Specify callback typedefs (e.g., `CipherFunc`)
   - Document stream contracts for reactive features
   - Define expected exception types and when they are thrown

2. **Document interface files**
   - Note which existing interfaces need modification
   - Describe new interfaces to be created
   - Reference contracts in the plan

### Phase 5: Project Structure

1. **Analyze current structure**
   Consider the two-project layout:
   - `lib/` -- core library (package: locker)
     - `lib/locker/` -- MFALocker class and Locker interface
     - `lib/security/` -- Cipher functions, biometric config, exceptions
     - `lib/storage/` -- Encrypted storage implementation, exceptions
     - `lib/erasable/` -- Secure memory management (ErasableByteArray)
     - `lib/utils/` -- Utilities (crypto, extensions, sync)
   - `example/lib/` -- demo Flutter app (mfa_demo)
     - `example/lib/features/` -- Feature modules (locker, settings)
     - `example/lib/di/` -- Dependency injection
   - `packages/biometric_cipher/` -- Platform channel plugin for biometrics
   - `packages/secure_mnemonic/` -- Mnemonic key storage plugin
   - `test/` -- Library unit tests with `test/mocks/`

2. **Plan structural changes**
   - List new directories to create
   - List new files to create (one primary type per file, name must match class)
   - Note modifications to existing structure
   - Follow file organization rules: extensions in separate files, sealed classes
     separate from widgets

### Phase 6: Task Breakdown

1. **Generate implementation tasks**
   Based on Research, Entities, Interfaces, and Structure:
   - Break down into discrete, testable tasks
   - Order tasks by dependency (prerequisites first)
   - Estimate complexity (S/M/L)
   - Group related tasks into phases
   - Include `make gen` step when Freezed models are created or modified

2. **Include verification tasks**
   - Unit tests for each component (using `mocktail`, Arrange/Act/Assert)
   - Integration tests for workflows
   - Verification commands:
     - `fvm flutter analyze --fatal-warnings --fatal-infos` (static analysis)
     - `fvm flutter test` (run tests)
     - `fvm dart format . --line-length 120` (formatting)
     - `make dcm-analyze` (Dart Code Metrics, for example app)

### Phase 7: Write Plan

1. **Create the implementation plan**
   - Write to `/specs/.current/plan.md`
   - Use the template structure below
   - Replace all placeholders with concrete details

2. **Review the plan**
   - Verify all sections are complete
   - Check that tasks are actionable
   - Ensure dependencies are clear

## Implementation Plan Template

```markdown
# Implementation Plan: [FEATURE]

**Input**: Feature specification from `/specs/.current/spec.md`
**User Input**: [If provided: "$ARGUMENTS" or "None"]

## Summary

[Extract from feature spec: primary requirement + technical approach from
research]

## Technical Context

**Language/Version**: Dart (SDK >=3.5.0), Flutter (>=3.35.0)
**FVM**: Flutter 3.35.1 (locked in `.ci-flutter-version`)
**Architecture**: UI -> BLoC (ActionBloc) -> Repository -> MFALocker Library
**State Management**: `flutter_bloc` + `action_bloc` (local package) + `freezed`
**Testing**: `mocktail` (Arrange/Act/Assert pattern)
**Target Platforms**: iOS, macOS, Android, Windows
**Project Type**: Two-project -- root `locker` library + `example/` Flutter app

## Project Structure

### Affected Areas

- **Core library (`lib/`)**: [Changes to locker, security, storage, etc.]
- **Example app (`example/lib/`)**: [Changes to features, di, etc.]
- **Platform plugins (`packages/`)**: [Changes if applicable]
- **Tests (`test/`)**: [New/modified test files]

### New Files

- `path/to/file.dart` - [Purpose, primary type]

### Modified Files

- `path/to/file.dart` - [What changes]

## Research

### [Topic 1]

[Findings and recommendations]

### [Topic 2]

[Findings and recommendations]

## Entities

### [Entity Name]

- **Type**: [Freezed model | BLoC event | BLoC state | BLoC action | Repository interface]
- **Fields**:
    - `field1`: type - description
    - `field2`: type - description
- **Relationships**: [Composition with other entities]
- **Validation**: [Dart type system constraints, Freezed assertions]
- **States**: [If applicable: state1 -> state2 -> state3]

## Dart Interfaces

### [Interface Name]

- **File**: `path/to/interface.dart`
- **Methods**:
    - `methodName(params)`: return type - description
- **Callback typedefs**: [If applicable]
- **Exceptions thrown**: [StorageException, BiometricException, etc.]

## Tasks

### Phase 1: [Foundation]

- [ ] **Task 1.1** (S): [Description]
    - Prerequisites: None
    - Verification: [How to verify]

- [ ] **Task 1.2** (M): [Description]
    - Prerequisites: Task 1.1
    - Verification: [How to verify]

### Phase 2: [Core Implementation]

- [ ] **Task 2.1** (L): [Description]
    - Prerequisites: Phase 1
    - Verification: [How to verify]
    - Note: Run `make gen` after Freezed model changes

### Phase 3: [Integration & Testing]

- [ ] **Task 3.1** (M): [Description]
    - Prerequisites: Phase 2
    - Verification: `fvm flutter analyze --fatal-warnings --fatal-infos` and
      `fvm flutter test`

```

## Guidelines

- **Absolute paths**: Always use absolute paths starting from repository root
- **Actionable tasks**: Each task should be completable in one work session
- **Testable outcomes**: Every task must have clear verification criteria
- **Dependency order**: Tasks must be ordered so prerequisites come first
- **Existing patterns**: Follow conventions from `docs/conventions.md` and
  architecture from `docs/vision.md`
- **Research-backed**: Technical decisions should reference research findings
- **Freezed generation**: Include `make gen` step when Freezed models change
- **MCP tools preferred**: Use `mcp__dart__analyze_files` over shell `flutter
  analyze`, `mcp__dart__run_tests` over shell `flutter test`,
  `mcp__dart__dart_format` over shell `dart format`
