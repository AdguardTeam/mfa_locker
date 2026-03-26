# MFA Demo - Development Conventions

## Purpose

This document defines coding standards and development practices for MFA Demo implementation. For architectural principles, design decisions, and the "why" behind our approach, refer to **[vision.md](vision.md)**.

**What this document covers:**
- Coding style and syntax rules
- Naming conventions
- Code structure patterns
- Development tools and workflow

**What vision.md covers:**
- Core principles (KISS, no overengineering, SOLID)
- Architecture and layer responsibilities
- Anti-patterns to avoid
- Project structure and file organization

## Quick Reference

**Key principles from vision.md:**
1. **KISS** - Simplest solution that works
2. **Single responsibility** - One thing per component
3. **Clarity over cleverness** - Readable code wins
4. **No overengineering** - Extend existing patterns, don't create new abstractions

**Architecture flow (see vision.md §3):**
```
UI → BLoC → Repository → MFALocker Library
```

**State management:**
- Use `action_bloc` pattern with Freezed
- Events (past tense), States (data), Actions (side effects)

## Naming Conventions

**Classes:**
- Interfaces: no prefix → `LockerRepository`
- Implementations: `Impl` suffix → `LockerRepositoryImpl`
- Private: `_` prefix → `_UnlockedScreenState`

**Events (past tense):**
- `UnlockRequested`, `EntryAdded`, `BiometricEnabledEvent`

**Actions (descriptive):**
- `ShowErrorAction`, `BiometricAuthenticationCancelledAction`

**Methods & Fields:**
- Public: camelCase → `unlockWithBiometric()`, `isBiometricEnabled`
- Private: `_` prefix → `_password`, `_handleError()`
- Loop vars: `i`, `j` or descriptive with `for-in`

## File Organization

### One Type Per File Rule

Each file should contain one primary type (class, enum, extension) that matches the file name. This satisfies the DCM `prefer-match-file-name` rule.

```dart
// ✅ GOOD: locker_bloc_biometric_stream.dart
extension LockerBlocBiometricStream on LockerBloc { ... }

// ❌ BAD: biometric_stream_extensions.dart with multiple extensions
extension LockerBlocBiometricStream on LockerBloc { ... }  // Name doesn't match file
extension SettingsBlocBiometricStream on SettingsBloc { ... }
```

### Extensions

**File naming:** Extension file name must match the extension name.
- `LockerBlocBiometricStream` → `locker_bloc_biometric_stream.dart`
- `AuthenticationResultExtensions` → `authentication_result_extensions.dart`

**Nullable vs non-nullable:** Use a single extension on the nullable type - it works for both:
```dart
// ✅ GOOD: Single extension works for both nullable and non-nullable
extension AuthenticationResultExtensions on AuthenticationResult? {
  bool get hasValidPassword => this != null && this!.password != null && this!.password!.isNotEmpty;
}

// Usage:
AuthenticationResult result = ...;
result.hasValidPassword;  // Works

AuthenticationResult? nullableResult = ...;
nullableResult.hasValidPassword;  // Also works

// ❌ BAD: Duplicate extensions
extension AuthenticationResultExtensions on AuthenticationResult { ... }
extension NullableAuthenticationResultExtensions on AuthenticationResult? { ... }
```

### Sealed Classes and Enums

Extract sealed classes and enums from widget files into dedicated files:
```
views/widgets/
├── authentication_bottom_sheet.dart      # Widget only
├── biometric_auth_result.dart            # Sealed class
├── confirmation_dialog.dart              # Widget only
└── confirmation_style.dart               # Enum
```

### Linter Rules

**Never ignore linter rules.** If a rule triggers, fix the underlying issue:
- `prefer-match-file-name` → Rename file or split into multiple files
- `unused_element` → Remove unused code
- `directives_ordering` → Run `dart fix --apply`

## Code Structure

### Class Member Order

```dart
class MyClass {
  // 1. Static constants (public, then private)
  static const String apiUrl = '...';
  
  // 2. Constructor fields (public, then private)
  final String userId;
  final ApiClient _client;
  
  // 3. Constructor
  MyClass({required this.userId, required ApiClient client}) : _client = client;
  
  // 4. Other private fields
  String? _cache;
  
  // 5. Public methods
  void doSomething() {}
  
  // 6. Private methods
  void _helper() {}
}
```

### BLoC Structure

```dart
class MyBloc extends ActionBloc<Event, State, Action> {
  final Repository _repository;
  
  MyBloc({required Repository repository})
      : _repository = repository,
        super(initialState) {
    on<EventType>(_onEventHandler);
  }
  
  Future<void> _onEventHandler(EventType event, Emitter emit) async {}
}
```

### Widget Lifecycle Order

```dart
class _MyWidgetState extends State<MyWidget> {
  @override
  void initState() { super.initState(); }
  
  @override
  Widget build(BuildContext context) => Container();
  
  @override
  void dispose() { super.dispose(); }
  
  void _customMethod() {}
}
```

## Syntax Rules

**Required:**
- Trailing commas for multi-line calls
- Curly braces for all control flow
- Arrow syntax for one-liners
- `for-in` over indexed loops
- `const` where possible
- Always check `context.mounted` before navigation/dialogs

**Examples:**
```dart
// ✅ GOOD
CustomButton(
  onPressed: () => print('Pressed'),
  child: const Text('Button'),  // Trailing comma
);

if (!context.mounted) {  // Curly braces
  return;
}

Widget build(BuildContext context) => const Text('Simple');  // Arrow function

for (final entry in entries) { process(entry); }  // for-in

// ❌ BAD
CustomButton(onPressed: () {}, child: Text('Button'))  // No trailing comma
if (!context.mounted) return;  // No braces
for (int i = 0; i < entries.length; i++) {}  // Indexed loop
```

## Layer Patterns

### Repository Pattern

**Responsibilities:** Create cipher functions, call MFALocker, handle exceptions
```dart
// BLoC passes raw password/no params
final entries = await repository.unlock(password);
final entries = await repository.unlockWithBiometric();

// Repository creates CipherFunc internally
Future<Map<EntryId, EntryMeta>> unlock(String password) async {
  final salt = await _locker.salt;
  final cipherFunc = PasswordCipherFunc(password: password, salt: salt!);
  await _locker.loadAllMeta(cipherFunc);
  return _locker.allMeta;
}

// Handle library exceptions
try {
  await _locker.operation();
} on DecryptFailedException {
  throw Exception('Incorrect password');
} on BiometricAuthenticationCancelledException {
  rethrow;  // Let BLoC handle biometric-specific errors
}
```

### BLoC Event Handler Pattern

**Responsibilities:** Emit loading state, call repository, emit result/action
```dart
Future<void> _onUnlockRequested(UnlockRequested event, Emitter emit) async {
  emit(state.copyWith(isLoading: true));
  try {
    final entries = await _repository.unlock(event.password);
    emit(state.copyWith(status: LockerStatus.unlocked, entries: entries, isLoading: false));
    dispatch(LockerAction.showSuccess('Unlocked'));
  } catch (e) {
    emit(state.copyWith(isLoading: false));
    dispatch(LockerAction.showError(e.toString()));
  }
}
```

### UI Widget Pattern

**Responsibilities:** Dispatch events, render states, handle actions
```dart
BlocActionListener<LockerBloc, LockerAction>(
  listener: (context, action) => action.map(
    showError: (a) => ScaffoldMessenger.of(context).showSnackBar(...),
    showSuccess: (a) => ScaffoldMessenger.of(context).showSnackBar(...),
  ),
  child: BlocBuilder<LockerBloc, LockerState>(
    builder: (context, state) => state.status == LockerStatus.unlocked
        ? UnlockedView()
        : LockedView(),
  ),
)
```

## Dependencies & Code Generation

**Dependencies:**
- Exact versions (no `^` caret)
- Alphabetical order (Flutter SDK first)
- Minimal set only

**Freezed usage:**
```dart
part 'my_class.freezed.dart';

@freezed
class MyClass with _$MyClass {
  const factory MyClass({required String value}) = _MyClass;
}
```

**Generate:** `flutter pub run build_runner build --delete-conflicting-outputs`

## Development Tools

### Dart MCP Tools

**MUST use MCP tools instead of shell commands for Dart/Flutter operations.**

**Setup:** `mcp1_add_roots(roots: [{"uri": "file:///absolute/path"}])`

**Common MCP Tools:**

| Operation | MCP Tool | Shell Equivalent |
|-----------|----------|------------------|
| Get deps | `mcp1_pub(command: "get", roots: [...])` | `flutter pub get` |
| Add package | `mcp1_pub(command: "add", packageName: "pkg", roots: [...])` | `flutter pub add pkg` |
| Format | `dart format lib --line-length 120` | Manual format |
| Fix | `mcp1_dart_fix(roots: [...])` | `dart fix --apply` |
| Analyze | `mcp1_analyze_files()` | `flutter analyze` |
| Test | `mcp1_run_tests(roots: [...])` | `flutter test` |
| Search | `mcp1_pub_dev_search(query: "...")` | Manual search |
| Hot reload | `mcp1_hot_reload()` | IDE hot reload |

**Formatting rule:** Always use `dart format lib --line-length 120` after code changes

**When shell is OK:**
- File operations: `cp`, `mv`, `mkdir`
- Git: `commit`, `push`, `pull`
- Build runner: `flutter pub run build_runner build --delete-conflicting-outputs`

## UI Best Practices

**Widget composition:**
- Extract large `build()` methods into private widget classes
- Small, reusable widgets over monolithic ones
- Use `ListView.builder` for long lists
- Extract complex dialogs to separate `StatefulWidget` classes
- Use `const` constructors everywhere possible

**State management:**
- StatefulWidget state fields MUST be private
- Avoid expensive operations in `build()`

## Code Quality

**Comments:**
- TODO format: `// TODO(firstLetter.lastName): Description`
- Use `///` for public APIs, explain why not what

**Null safety:**
- Avoid `!` operator unless guaranteed non-null
- Use `?` and `??` appropriately

**Async:**
- Always use `async`/`await`
- Wrap in try-catch for error handling
- `Future` for single ops, `Stream` for sequences

## Summary

**Essential rules:**
1. Follow **vision.md** architecture (UI → BLoC → Repository → Library)
2. Use `action_bloc` + Freezed for state management
3. Use context extensions for dependencies
4. Repository creates cipher functions and wraps MFALocker
5. Prefer Dart MCP tools over shell commands
6. Format with `dart format lib --line-length 120`
7. KISS principle - simplest working solution
8. Check `context.mounted` before navigation/dialogs

**For complete architectural guidance, see [vision.md](vision.md)**
