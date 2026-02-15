# MFA Demo - Biometric Integration Technical Vision

## 1. Core Principles

### KISS Above All
This integration follows the **Keep It Simple, Stupid** principle rigorously:
- **Minimal code changes** - Extend existing patterns, don't reinvent them
- **No new abstractions** - Use existing BLoC, Repository, and UI patterns
- **Single responsibility** - Each component does one thing well
- **Clarity over cleverness** - Readable code beats clever code

### No Overengineering
We explicitly avoid:
- ❌ Complex state machines for biometric flows
- ❌ Custom error recovery frameworks
- ❌ Abstract factories or strategy patterns for cipher function creation
- ❌ Elaborate dependency injection frameworks
- ❌ Multi-level service abstractions

We embrace:
- ✅ Simple if/else error handling
- ✅ Direct repository method calls
- ✅ Straightforward BLoC event handlers
- ✅ Constructor-based dependency injection
- ✅ Flat architecture - Repository → BLoC → UI

### Core Development Principles
- **SOLID principles** - Single responsibility, open/closed, dependency inversion
- **Composition over inheritance** - Build complex functionality from simple parts
- **Immutability** - Prefer immutable data structures and const widgets
- **Separation of concerns** - Clear boundaries between Repository, BLoC, and UI layers
- **Functional patterns** - Prefer declarative, functional code style

### Anti-Patterns to Avoid

#### ❌ DON'T: Create Multiple BioCipherFunc Instances
```dart
// BAD - Creating new instance every time
Future<void> unlockWithBiometric() async {
  final bioCipherFunc = BioCipherFunc(keyTag: 'mfa_demo_bio_key');
  await bioCipherFunc.configure(...);
  await _locker.loadAllMeta(bioCipherFunc);
}
```

#### ✅ DO: Create Once, Configure Once, Reuse
```dart
// GOOD - Single creation pattern
BioCipherFunc _createBioCipherFunc() {
  return BioCipherFunc(keyTag: 'mfa_demo_bio_key');
}
```

#### ❌ DON'T: Wrap Library Errors in Custom Exceptions
```dart
// BAD - Unnecessary wrapping
try {
  await bioCipherFunc.encrypt(data);
} catch (e) {
  throw CustomBiometricException(e); // Don't do this
}
```

#### ✅ DO: Let Library Exceptions Propagate
```dart
// GOOD - Handle specific exceptions
try {
  await bioCipherFunc.encrypt(data);
} on BiometricAuthenticationCancelledException {
  // Handle cancellation
} on BiometricKeyNotFoundException {
  // Handle key not found
}
```

#### ❌ DON'T: Store Biometric State in Multiple Places
```dart
// BAD - State duplication
class LockerBloc {
  bool _isBiometricEnabled = false; // ❌
}
class LockerRepository {
  bool _biometricEnabled = false; // ❌ Duplicate state
}
```

#### ✅ DO: Single Source of Truth
```dart
// GOOD - State only in BLoC
class LockerBloc {
  bool get isBiometricEnabled => state.isBiometricEnabled; // ✅
}
```

#### ❌ DON'T: Create Complex Helper Classes
```dart
// BAD - Overengineering
class BiometricConfigurationManager {
  final BiometricConfigFactory _factory;
  final BiometricStateValidator _validator;
  // ... unnecessary complexity
}
```

#### ✅ DO: Simple Helper Methods
```dart
// GOOD - Simple, direct
BiometricConfig _createBiometricConfig() {
  return BiometricConfig(
    promptTitle: 'Authenticate',
    promptSubtitle: 'Use biometrics to unlock',
    cancelButtonText: 'Cancel',
  );
}
```

#### ❌ DON'T: Abstract Away BioCipherFunc Creation
```dart
// BAD - Unnecessary abstraction
abstract class CipherFuncFactory {
  CipherFunc create();
}
class BioCipherFuncFactory implements CipherFuncFactory { ... }
```

#### ✅ DO: Direct Instantiation
```dart
// GOOD - Clear and simple
final bioCipherFunc = BioCipherFunc(keyTag: 'mfa_demo_bio_key');
```

#### ❌ DON'T: Create Separate Biometric BLoCs
```dart
// BAD - Unnecessary separation
class BiometricBloc extends Bloc<BiometricEvent, BiometricState> { ... }
class LockerBloc extends Bloc<LockerEvent, LockerState> { ... }
```

#### ✅ DO: Extend Existing BLoC
```dart
// GOOD - Add biometric events to existing LockerBloc
class LockerBloc extends Bloc<LockerEvent, LockerState> {
  // Add biometric events here
}
```

#### ❌ DON'T: Ignore context.mounted Checks
```dart
// BAD - Missing mounted check
void _showError(String message) {
  Navigator.pop(context); // ❌ Context might be unmounted
}
```

#### ✅ DO: Always Check context.mounted
```dart
// GOOD - Safe context usage
void _showError(String message) {
  if (!context.mounted) {
    return;
  }
  Navigator.pop(context);
}
```

### Simplicity Checklist
Before adding any code, ask:
1. **Is this the simplest solution?**
2. **Can we use existing patterns instead?**
3. **Will this confuse someone reading it in 6 months?**
4. **Is this solving a real problem, not a hypothetical one?**

If any answer is "no" or "yes" to #3, simplify further.

## 2. Project Structure

### Existing Structure (No Changes)
The current mfa_demo structure remains intact:

```
lib/
├── core/                   # Shared utilities
│   ├── constants/          # App constants
│   ├── data/storages/      # Settings persistence
│   ├── extensions/         # Context extensions
│   └── utils/              # Utility functions
├── di/                     # Dependency injection
│   ├── dependency_scope.dart
│   └── factories/          # Factory interfaces & implementations
└── features/
    ├── locker/             # Main locker feature
    │   ├── bloc/           # Business logic (BLoC)
    │   ├── data/           # Data layer
    │   │   ├── models/     # Data models
    │   │   └── repositories/  # Repository implementation
    │   └── views/          # UI layer
    │       ├── auth/       # Authentication screens
    │       ├── storage/    # Storage management screens
    │       └── widgets/    # Reusable widgets
    └── settings/           # Settings feature
        ├── bloc/           # Settings BLoC
        ├── data/models/    # Settings models
        └── views/          # Settings screens
```

### Biometric Integration - Files to Modify

#### 1. Constants Layer
**File:** `lib/core/constants/app_constants.dart`
- Add biometric key tag constant
- Add default biometric prompt strings

#### 2. Repository Layer
**File:** `lib/features/locker/data/repositories/locker_repository.dart`
- Add biometric methods to `LockerRepository` interface
- Implement biometric methods in `LockerRepositoryImpl`
- Add helper: `_createBioCipherFunc()`
- Add helper: `_configureBioCipherFunc()`
- Add helper: `_checkBiometricAvailability()`

#### 3. BLoC Layer
**File:** `lib/features/locker/bloc/locker_event.dart`
- Add: `CheckBiometricAvailabilityEvent`
- Add: `EnableBiometricEvent`
- Add: `DisableBiometricEvent`
- Add: `UnlockWithBiometricEvent`
- Add: `AddEntryWithBiometricEvent`
- Add: `ReadEntryWithBiometricEvent`
- Add: `DeleteEntryWithBiometricEvent`

**File:** `lib/features/locker/bloc/locker_state.dart`
- Add: `bool isBiometricAvailable`
- Add: `bool isBiometricEnabled`

**File:** `lib/features/locker/bloc/locker_action.dart`
- Add: `BiometricAuthenticationCancelledAction`
- Add: `BiometricAuthenticationFailedAction`
- Add: `BiometricNotAvailableAction`

**File:** `lib/features/locker/bloc/locker_bloc.dart`
- Add event handlers for all biometric events
- Add initialization logic to check biometric availability

#### 4. UI Layer - Existing Files to Modify
**File:** `lib/features/settings/views/settings_screen.dart`
- Add biometric toggle switch

**File:** `lib/features/locker/views/auth/login_screen.dart`
- Add biometric unlock button

**File:** `lib/features/locker/views/storage/*.dart`
- Add biometric authentication options where needed

#### 5. UI Layer - New Widget Files to Create
**File:** `lib/features/locker/views/widgets/biometric_unlock_button.dart`
- Reusable biometric unlock button for login screen
- Shows fingerprint/Face ID icon based on platform

**File:** `lib/features/locker/views/widgets/enable_biometric_dialog.dart`
- Dialog for enabling biometric authentication
- Explains functionality and requires password confirmation

**File:** `lib/features/locker/views/widgets/disable_biometric_dialog.dart`
- Dialog for disabling biometric authentication
- Requires password confirmation

**File:** `lib/features/locker/views/widgets/biometric_auth_option.dart`
- Reusable widget showing "Use Biometric" option in password dialogs
- Used in add/read/delete entry flows

### File Organization Principles

1. **Separate widgets** - Create dedicated widget files for reusability
2. **Clear naming** - Include "biometric" in all related file/class names
3. **Extend, don't duplicate** - Add to existing files where appropriate
4. **Colocation** - Biometric widgets live in the same widgets folder as other dialogs

### Naming Conventions

**Events:** `*BiometricEvent` pattern
- `CheckBiometricAvailabilityEvent`
- `EnableBiometricEvent`
- `UnlockWithBiometricEvent`

**Actions:** `Biometric*Action` pattern
- `BiometricAuthenticationCancelledAction`
- `BiometricAuthenticationFailedAction`

**Widgets:** `biometric_*` file naming
- `biometric_unlock_button.dart`
- `enable_biometric_dialog.dart`
- `biometric_auth_option.dart`

**Methods:** `*Biometric*` pattern
- `enableBiometric()`
- `unlockWithBiometric()`
- `_createBioCipherFunc()`

### Where NOT to Put Biometric Code

❌ **Don't create:**
- `lib/features/biometric/` - No separate feature folder
- `lib/core/biometric/` - No core biometric abstractions
- `lib/services/biometric_service.dart` - No separate service layer
- `lib/features/locker/data/biometric_repository.dart` - No separate repository

✅ **Do extend:**
- Existing `LockerRepository`
- Existing `LockerBloc`
- Existing view files
- Add new widget files in existing `widgets/` folder

### Summary of New Files

```
lib/core/constants/
  app_constants.dart                          # MODIFY - Add biometric constants

lib/features/locker/views/widgets/
  biometric_unlock_button.dart                # NEW
  enable_biometric_dialog.dart                # NEW
  disable_biometric_dialog.dart               # NEW
  biometric_auth_option.dart                  # NEW
```

**Total new files:** 4 widgets
**Total modified files:** ~10 existing files

## 3. Architecture Overview

### High-Level Architecture (Unchanged)

The biometric integration follows the existing 3-layer architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                        UI Layer                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Login Screen │  │ Settings     │  │ Entry        │      │
│  │              │  │ Screen       │  │ Dialogs      │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                 │                 │               │
│         └─────────────────┴─────────────────┘               │
│                           │                                 │
│                           ▼                                 │
│  ┌────────────────────────────────────────────────────┐    │
│  │              LockerBloc (State Management)         │    │
│  │  - Handles events (password + biometric)           │    │
│  │  - Emits states (loading, unlocked, locked, etc.)  │    │
│  │  - Emits actions (errors, success notifications)   │    │
│  └────────────────────┬───────────────────────────────┘    │
└─────────────────────────┼──────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Repository Layer                          │
│  ┌────────────────────────────────────────────────────┐    │
│  │          LockerRepository (Data Access)            │    │
│  │  - Password operations: unlock(), addEntry(), etc. │    │
│  │  - Biometric operations: unlockWithBiometric(), etc.│   │
│  │  - Creates PasswordCipherFunc                      │    │
│  │  - Creates BioCipherFunc                           │    │
│  └────────────────────┬───────────────────────────────┘    │
└─────────────────────────┼──────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                     Library Layer                            │
│  ┌────────────────────────────────────────────────────┐    │
│  │              MFALocker (Core Logic)                │    │
│  │  - loadAllMeta(CipherFunc)                         │    │
│  │  - write/read/delete with CipherFunc               │    │
│  │  - enableBiometry(BioCipherFunc, PasswordCipherFunc)│   │
│  │  - disableBiometry(BioCipherFunc, PasswordCipherFunc)│  │
│  └────────────────────┬───────────────────────────────┘    │
│                       │                                     │
│         ┌─────────────┴─────────────┐                      │
│         ▼                           ▼                      │
│  ┌──────────────┐          ┌──────────────┐               │
│  │PasswordCipher│          │BioCipherFunc │               │
│  │Func (pwd)    │          │(biometric)   │               │
│  └──────────────┘          └──────────────┘               │
└─────────────────────────────────────────────────────────────┘
```

### Layer Responsibilities

#### UI Layer (Views/Widgets)
**Responsibility:** User interaction and visual feedback

**Password Operations (Existing):**
- Collect password input
- Display loading/success/error states
- Show password dialogs

**Biometric Operations (New):**
- Show biometric unlock button
- Display biometric enable/disable toggle
- Show biometric auth option in dialogs
- Handle biometric-specific error messages

**What it does NOT do:**
- ❌ Create BioCipherFunc instances
- ❌ Call MFALocker directly
- ❌ Handle biometric exceptions
- ❌ Store biometric state

#### BLoC Layer (Business Logic)
**Responsibility:** State management and business logic orchestration

**Password Operations (Existing):**
- Handle password events (unlock, add entry, etc.)
- Emit loading/success/error states
- Call repository methods with password

**Biometric Operations (New):**
- Handle biometric events (enable, disable, unlock, etc.)
- Maintain biometric state (available, enabled)
- Map biometric exceptions to actions
- Emit biometric-specific actions

**What it does NOT do:**
- ❌ Create cipher functions (delegates to Repository)
- ❌ Call MFALocker directly
- ❌ Perform encryption/decryption

#### Repository Layer (Data Access)
**Responsibility:** Data operations and cipher function creation

**Password Operations (Existing):**
- Create PasswordCipherFunc from password string
- Call MFALocker methods with PasswordCipherFunc
- Convert between string and EntryMeta/EntryValue

**Biometric Operations (New):**
- Check biometric availability
- Create and configure BioCipherFunc
- Call MFALocker biometric methods
- Handle biometric wrap management

**What it does NOT do:**
- ❌ Emit UI actions or events
- ❌ Manage state (only repository-level caching)
- ❌ Directly interact with UI

#### Library Layer (MFALocker)
**Responsibility:** Core encryption, storage, and security

**Operations (Provided by locker library):**
- Manage encrypted storage
- Handle multiple wraps (password + biometric)
- Perform encryption/decryption with CipherFunc
- Auto-lock timer management

**No changes needed** - Library already supports biometric operations.

### Key Architectural Principles

1. **Single Direction Data Flow:** UI → BLoC → Repository → MFALocker
2. **Clear Boundaries:** Each layer has one responsibility
3. **Exception Handling:** Exceptions bubble up, BLoC maps to actions, UI displays
4. **State Source of Truth:** BLoC holds UI state, MFALocker holds data state
5. **No Shortcuts:** Never bypass layers (e.g., UI calling Repository directly)

### Biometric State Management

**State Location:** `LockerState` in BLoC
```dart
class LockerState {
  final bool isBiometricAvailable;  // Device supports biometrics
  final bool isBiometricEnabled;    // User enabled biometric for this storage
  // ... other existing fields
}
```

**State Updates:**
- `isBiometricAvailable`: Set during initialization, doesn't change
- `isBiometricEnabled`: Updated when user enables/disables biometric

**Not Stored:**
- Current biometric authentication status (ephemeral, prompt-based)
- Biometric key existence (checked via library exceptions)

---

## 4. Biometric Signaling Pattern (Post-Refactor)

- UI dispatches biometric events (unlock, add, view, delete) to `LockerBloc` (for example, `unlockWithBiometricRequested`, `addEntryWithBiometricRequested`, `readEntryWithBiometricRequested`, and `deleteEntryWithBiometricRequested`).
- `LockerBloc` performs work via `LockerRepository`, updates `LockerState` (entries, viewing entry, `loadState`, biometric state), and emits `LockerAction` variants:
  - `biometricAuthenticationSucceeded` to signal successful biometric authentication.
  - `biometricAuthenticationFailed`, `biometricNotAvailable`, and `biometricAuthenticationCancelled` for failure and cancellation cases.
- `AuthenticationBottomSheet` listens to `LockerAction` and:
  - Closes itself on `biometricAuthenticationSucceeded`.
  - Shows inline error messages for failure or unavailability without navigating away.

All previous UI/BLoC `Completer` wiring for biometric flows has been removed. Biometric flows now rely purely on events + state + actions, which:
- reduces coupling between UI and BLoC,
- simplifies reasoning about flows,
- and keeps the implementation aligned with the `action_bloc` pattern.

*This document continues with additional sections covering Data Model, Core Workflows, Logging Strategy, and Biometric Configuration.*
