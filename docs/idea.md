# MFA Demo - Biometric Authentication Integration

## Overview

This document analyzes the feasibility of integrating biometric authentication (fingerprint, Face ID, etc.) into the **mfa_demo** application to demonstrate the biometric encryption/decryption capabilities added to the **locker** library via `BioCipherFunc`.

## Executive Summary

**FEASIBILITY: ✅ HIGHLY FEASIBLE**

The locker library already provides complete biometric support through:
- `BioCipherFunc` class for biometric-based encryption/decryption
- `MFALocker.enableBiometry()` and `MFALocker.disableBiometry()` methods
- Full integration with the secure_mnemonic plugin for platform-specific biometric APIs

Integration into mfa_demo is straightforward and aligns well with the existing architecture.

---

## Current State Analysis

### Locker Library Biometric Support

The locker library provides comprehensive biometric functionality:

#### 1. **BioCipherFunc** (`packages/locker/lib/security/models/bio_cipher_func.dart`)

A `CipherFunc` implementation that uses device biometrics for encryption/decryption:

**Key Features:**
- Extends `CipherFunc` with `Origin.bio`
- Uses `SecureMnemonicProvider` for platform-specific biometric operations
- Requires configuration with `BiometricConfig` before use
- Supports biometric key generation, encryption, decryption
- Comprehensive error handling with custom exceptions

**Key Methods:**
```dart
// Configure biometric prompts (must be called before use)
Future<void> configure(BiometricConfig config)

// Encrypt data using biometrics
Future<Uint8List> encrypt(ErasableByteArray data)

// Decrypt data using biometrics
Future<ErasableByteArray> decrypt(Uint8List data)

// Generate biometric key for the tag
Future<void> generateKeyForTag()

// Check if biometrics are available on device
Future<bool> isBiometricAvailable()

// Clean up biometric key
void erase()
```

**Exception Types:**
- `BiometricNotConfiguredException` - BioCipherFunc not configured
- `BiometricKeyNotFoundException` - Key not found for the tag
- `BiometricAuthenticationCancelledException` - User cancelled authentication
- `BiometricNotAvailableException` - Biometrics not supported on device

#### 2. **BiometricConfig** (`packages/locker/lib/security/models/biometric_config.dart`)

Configuration for biometric prompts:

```dart
class BiometricConfig {
  final String promptTitle;
  final String promptSubtitle;
  final String cancelButtonText;
  final String? windowsAuthData;  // Optional for Windows
}
```

#### 3. **MFALocker Integration**

MFALocker already has built-in biometric methods:

```dart
// Enable biometric authentication (adds bio wrap alongside password wrap)
Future<void> enableBiometry({
  required BioCipherFunc bioCipherFunc,
  required PasswordCipherFunc passwordCipherFunc,
})

// Disable biometric authentication (removes bio wrap, keeps password wrap)
Future<void> disableBiometry({
  required BioCipherFunc bioCipherFunc,
  required PasswordCipherFunc passwordCipherFunc,
})
```

**Key Insight:** The library supports **multiple wraps** - biometric and password can coexist. Users can unlock with either method.

### Current mfa_demo Architecture

The demo app uses a clean BLoC architecture:

**Structure:**
```
lib/features/locker/
├── bloc/               # Business logic (LockerBloc)
├── data/
│   ├── models/        # Repository state models
│   └── repositories/  # LockerRepository wrapping MFALocker
└── views/
    ├── auth/          # Authentication screens (login, init)
    ├── storage/       # Storage management screens
    └── widgets/       # Reusable widgets
```

**Current Authentication Flow:**
1. **Password-Only:** All operations require password entry
2. **PasswordCipherFunc:** Created by `SecurityProviderImpl.authenticatePassword()`
3. **Repository Layer:** Wraps MFALocker, converts password strings to cipher functions
4. **BLoC Layer:** Handles events, emits states/actions

---

## Integration Requirements

### 1. **Repository Layer Extensions**

Add biometric methods to `LockerRepository`:

```dart
abstract class LockerRepository {
  // Existing methods...
  
  /// Check if biometric authentication is available on device
  Future<bool> isBiometricAvailable();
  
  /// Check if biometric authentication is enabled for this storage
  Future<bool> isBiometricEnabled();
  
  /// Enable biometric authentication
  Future<void> enableBiometric({
    required String password,  // Current password for verification
  });
  
  /// Disable biometric authentication
  Future<void> disableBiometric({
    required String password,  // Password for verification
  });
  
  /// Unlock storage using biometrics
  Future<void> unlockWithBiometric();
  
  /// Add entry using biometric authentication
  Future<void> addEntryWithBiometric({
    required String name,
    required String value,
  });
  
  /// Read entry using biometric authentication
  Future<String> readEntryWithBiometric({
    required String name,
  });
  
  /// Delete entry using biometric authentication
  Future<void> deleteEntryWithBiometric({
    required String name,
  });
}
```

**Implementation Notes:**
- Create `BioCipherFunc` with a consistent `keyTag` (e.g., "mfa_demo_bio_key")
- Configure `BioCipherFunc` with localized `BiometricConfig`
- Store biometric enablement state (can check if bio wrap exists via storage)
- Generate biometric key during `enableBiometric()`

### 2. **State Management Updates**

**New BLoC Events:**
```dart
// Biometric availability check
sealed class CheckBiometricAvailabilityEvent extends LockerEvent {}

// Biometric settings
sealed class EnableBiometricEvent extends LockerEvent {
  final String password;
}

sealed class DisableBiometricEvent extends LockerEvent {
  final String password;
}

// Biometric operations
sealed class UnlockWithBiometricEvent extends LockerEvent {}

sealed class AddEntryWithBiometricEvent extends LockerEvent {
  final String name;
  final String value;
}

sealed class ReadEntryWithBiometricEvent extends LockerEvent {
  final String name;
}

sealed class DeleteEntryWithBiometricEvent extends LockerEvent {
  final String name;
}
```

**New BLoC States/Actions:**
```dart
// State additions
final bool isBiometricAvailable;
final bool isBiometricEnabled;

// Actions
sealed class BiometricNotAvailableAction extends LockerAction {}
sealed class BiometricAuthenticationCancelledAction extends LockerAction {}
sealed class BiometricAuthenticationFailedAction extends LockerAction {
  final String message;
}
```

### 3. **UI Components**

#### A. Settings Screen
- **Biometric Toggle:** Enable/disable biometric authentication
  - Only visible if `isBiometricAvailable == true`
  - Requires password confirmation to enable/disable
  - Clear indication of current status

#### B. Login Screen
- **Biometric Button:** Quick unlock with fingerprint/Face ID
  - Only visible if `isBiometricEnabled == true`
  - Fallback to password if biometric fails/cancelled
  - Clear visual indicator (fingerprint icon, Face ID icon)

#### C. Operation Screens (Add/View/Delete Entry)
- **Biometric Option:** Alternative to password entry
  - Show biometric option alongside password field
  - "Use biometric" button when enabled
  - Same error handling as password authentication

#### D. Dialogs
- **Enable Biometric Dialog:**
  - Explain what happens (additional unlock method)
  - Password entry for verification
  - Trigger biometric enrollment

- **Biometric Prompt:** (Handled by OS)
  - Native platform dialogs
  - Configured via `BiometricConfig` with localized strings

### 4. **Security Provider Extensions**

Extend `SecurityProvider` (or create new helper):

```dart
abstract class SecurityProvider {
  // Existing...
  Future<PasswordCipherFunc> authenticatePassword(...);
  
  // New biometric methods
  Future<BioCipherFunc> createBioCipherFunc({
    required String keyTag,
  });
  
  Future<void> configureBiometric({
    required BioCipherFunc bioCipherFunc,
    BiometricConfig? config,
  });
}
```

**Default Configuration:**
```dart
BiometricConfig(
  promptTitle: 'Authenticate',
  promptSubtitle: 'Use biometrics to access your secure storage',
  cancelButtonText: 'Cancel',
)
```

Support for localization can be added later.

---

## Technical Considerations

### 1. **Platform Support**

The `secure_mnemonic` plugin supports:
- ✅ **iOS:** Face ID, Touch ID (via Keychain)
- ✅ **Android:** Fingerprint, Face Unlock (via BiometricPrompt API)
- ✅ **macOS:** Touch ID (via Keychain)
- ✅ **Windows:** Windows Hello (via Windows Credential Manager)
- ❓ **Linux:** Limited/no support (graceful degradation needed)
- ❌ **Web:** Not supported (graceful degradation needed)

**Handling Unsupported Platforms:**
- Check `isBiometricAvailable()` at startup
- Hide biometric UI elements if unavailable
- Fall back to password-only authentication

### 2. **Key Storage and Management**

**Key Tag Strategy:**
- Use a consistent key tag across app lifecycle: `"mfa_demo_bio_key"`
- Key is stored in platform secure storage (Keychain, Keystore, etc.)
- Key persists across app restarts but not across device resets

**Key Lifecycle:**
- **Generation:** On `enableBiometric()`, call `bioCipherFunc.generateKeyForTag()`
- **Deletion:** On `disableBiometric()`, call `bioCipherFunc.erase()` (triggers key deletion)
- **Re-enrollment:** If key is deleted (e.g., user changes biometrics), require re-enabling

### 3. **Dual Authentication Model**

The library supports **multiple wraps**:
- Password wrap (always present)
- Biometric wrap (optional)

**User Experience:**
- Password is always required for critical operations (enable biometric, change password, erase storage)
- Biometric is a convenience feature for unlock and entry operations
- Disabling biometric doesn't affect password authentication

### 4. **Error Handling**

**BioCipherFunc Exceptions:**

| Exception | Scenario | UI Handling |
|-----------|----------|-------------|
| `BiometricNotConfiguredException` | BioCipherFunc not configured | Show error, log issue |
| `BiometricKeyNotFoundException` | Key deleted/not generated | Disable biometric, require re-enrollment |
| `BiometricAuthenticationCancelledException` | User cancelled prompt | Show snackbar, return to previous screen |
| `BiometricNotAvailableException` | Biometrics not supported | Disable biometric UI, show message |

**User-Facing Messages:**
- "Biometric authentication cancelled"
- "Biometric authentication not available"
- "Biometric key not found. Please re-enable biometric authentication."
- "An error occurred. Please use your password instead."

### 5. **Settings Persistence**

The library itself handles biometric wrap persistence. The app only needs to:
- Check if biometric wrap exists (can infer from successful unlock attempt)
- Cache `isBiometricEnabled` state in BLoC
- Refresh state on app restart

**Optional:** Store UI preference in `SharedPreferences` for faster initial render.

### 6. **Auto-Lock Behavior**

No changes needed to auto-lock behavior:
- Timer still applies when unlocked (regardless of unlock method)
- Biometric authentication still required after auto-lock
- Background lock behavior unchanged

---

## Implementation Strategy

### Phase 1: Repository Layer (Core Integration)

**Scope:**
1. Add biometric methods to `LockerRepository` interface and implementation
2. Create helper methods for `BioCipherFunc` creation and configuration
3. Add error mapping for biometric exceptions

**Complexity:** Medium
**Dependencies:** None (uses existing locker library features)

### Phase 2: State Management

**Scope:**
1. Add biometric-related events to `LockerBloc`
2. Add biometric state fields (`isBiometricAvailable`, `isBiometricEnabled`)
3. Add biometric actions for UI feedback
4. Implement event handlers for biometric operations
5. Update existing state transitions to include biometric info

**Complexity:** Medium
**Dependencies:** Phase 1

### Phase 3: UI Components

**Scope:**
1. Add biometric toggle to Settings screen
2. Add biometric button to Login screen
3. Add biometric option to entry operation dialogs
4. Implement enable/disable biometric dialogs
5. Add biometric icons and visual indicators
6. Handle biometric-specific error states

**Complexity:** Medium
**Dependencies:** Phase 2

### Phase 4: Polish & Manual Verification

**Scope:**
1. Localization for biometric prompts
2. Manual testing on available platforms (iOS, Android, macOS, Windows)
3. Manual verification of error scenarios (key deletion, cancellation, user workflows)
4. Accessibility improvements
5. Documentation updates (README)

**Testing Approach:**
- All testing will be performed **manually** at this stage
- Focus on functional verification and user experience validation
- Test on real devices where biometric hardware is available
- Verify graceful degradation on platforms without biometric support
- Unit and integration tests are a **separate task** and not currently in scope

**Complexity:** Low
**Dependencies:** Phase 3

---

## Risk Assessment

### High Priority Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Platform incompatibility | Medium | High | Early testing on all platforms; graceful degradation |
| Key deletion by OS/user | Low | Medium | Clear messaging; easy re-enrollment flow |
| Biometric spoofing concerns | Low | Low | Use OS-provided security; educate users |

### Medium Priority Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Complex error scenarios | Medium | Medium | Comprehensive error handling; fallback to password |
| User confusion (dual auth) | Medium | Low | Clear UI/UX; contextual help text |

### Low Priority Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Performance impact | Low | Low | Biometric ops are async; minimal UI blocking |

---

## Benefits of Integration

### 1. **Demonstrates Library Capability**
- Showcases the dual-authentication model
- Highlights security best practices (biometric + password)
- Educational value for developers evaluating the library

### 2. **Improved User Experience**
- Faster unlock (no typing required)
- Seamless entry operations
- Modern authentication UX

### 3. **Real-World Use Case**
- Aligns with industry standards (banking apps, password managers)
- Shows practical implementation patterns
- Provides reference code for library users

### 4. **Minimal Additional Complexity**
- Library already handles all cryptographic complexity
- Platform integration via secure_mnemonic plugin
- Fits naturally into existing architecture

---

## Alternative Approaches Considered

### 1. **Biometric-Only Mode** ❌
- **Description:** Allow users to use biometric exclusively, no password
- **Rejected:** Password is essential for account recovery and critical operations

### 2. **Replace Password with Biometric** ❌
- **Description:** Use biometric as primary auth, password as backup
- **Rejected:** Goes against security best practices; password should be primary

### 3. **Optional Demo Mode Toggle** ⚠️
- **Description:** Make biometric integration optional via feature flag
- **Consideration:** Could be useful for platforms without biometric support
- **Decision:** Implement graceful degradation instead (hide UI when unavailable)

---

## Success Criteria

### Functional Requirements
- ✅ Users can enable/disable biometric authentication
- ✅ Users can unlock storage using biometrics
- ✅ Users can perform entry operations (add/read/delete) using biometrics
- ✅ Password authentication remains available as fallback
- ✅ Graceful handling of biometric unavailability

### Non-Functional Requirements
- ✅ Biometric operations complete within 3 seconds (excluding user interaction)
- ✅ Clear error messages for all failure scenarios
- ✅ Accessible UI for biometric features
- ✅ Consistent behavior across supported platforms

### User Experience Requirements
- ✅ Intuitive biometric enable/disable flow
- ✅ Clear visual distinction between password and biometric options
- ✅ No confusing state transitions
- ✅ Helpful contextual information

---

## Conclusion

**RECOMMENDATION: ✅ PROCEED WITH INTEGRATION**

The biometric functionality is **highly feasible** and **well-aligned** with the mfa_demo's goals:

### Strengths
- ✅ Complete library support (BioCipherFunc, MFALocker methods)
- ✅ Fits naturally into existing BLoC architecture
- ✅ Minimal risk (well-tested library code)
- ✅ High educational value for demo app
- ✅ Modern UX improvement

### Considerations
- ⚠️ Platform-specific manual testing required
- ⚠️ Error handling must be comprehensive
- ⚠️ UI/UX clarity is critical for dual authentication

### Estimated Effort
- **Development:** 3-5 days (full-time)
- **Manual Testing:** 1-2 days (functional verification on available platforms)
- **Documentation:** 0.5 day

**Note:** Unit and integration tests are not included in this estimate and will be addressed as a separate task if needed.

### Next Steps
1. Review and approve this feasibility analysis
2. Create detailed implementation plan (iteration-based, per workflow.md)
3. Begin Phase 1 (Repository Layer) implementation
4. Iterative development following mfa_demo conventions

---

## Appendix: Code Examples

### Example: Enabling Biometric Authentication

```dart
// Repository implementation
Future<void> enableBiometric({required String password}) async {
  // 1. Verify password
  final passwordCipherFunc = await _createPasswordCipherFunc(password: password);
  
  // 2. Create and configure BioCipherFunc
  final bioCipherFunc = BioCipherFunc(keyTag: 'mfa_demo_bio_key');
  await bioCipherFunc.configure(BiometricConfig(
    promptTitle: 'Enable Biometric Authentication',
    promptSubtitle: 'Use your biometric to access the vault',
    cancelButtonText: 'Cancel',
  ));
  
  // 3. Check availability
  await bioCipherFunc.isBiometricAvailable();
  
  // 4. Generate key
  await bioCipherFunc.generateKeyForTag();
  
  // 5. Enable in locker
  await _locker.enableBiometry(
    bioCipherFunc: bioCipherFunc,
    passwordCipherFunc: passwordCipherFunc,
  );
}
```

### Example: Unlocking with Biometric

```dart
// Repository implementation
Future<void> unlockWithBiometric() async {
  // 1. Create and configure BioCipherFunc
  final bioCipherFunc = BioCipherFunc(keyTag: 'mfa_demo_bio_key');
  await bioCipherFunc.configure(BiometricConfig(
    promptTitle: 'Unlock Vault',
    promptSubtitle: 'Use your biometric to unlock',
    cancelButtonText: 'Use Password',
  ));
  
  // 2. Unlock (triggers biometric prompt)
  await _locker.loadAllMeta(bioCipherFunc);
}
```

### Example: Error Handling in BLoC

```dart
// BLoC event handler
Future<void> _onUnlockWithBiometric(
  UnlockWithBiometricEvent event,
  Emitter<LockerState> emit,
) async {
  emit(state.copyWith(isLoading: true));
  
  try {
    await _repository.unlockWithBiometric();
    // State update handled by stream subscription
  } on BiometricAuthenticationCancelledException {
    emit(BiometricAuthenticationCancelledAction());
  } on BiometricKeyNotFoundException {
    emit(BiometricAuthenticationFailedAction(
      message: 'Biometric key not found. Please re-enable biometric authentication.',
    ));
  } on BiometricNotAvailableException {
    emit(BiometricAuthenticationFailedAction(
      message: 'Biometric authentication is not available.',
    ));
  } catch (e) {
    emit(BiometricAuthenticationFailedAction(
      message: 'An error occurred. Please use your password instead.',
    ));
  } finally {
    emit(state.copyWith(isLoading: false));
  }
}
```

---

**Document Version:** 1.0  
**Last Updated:** 2025-01-11  
**Author:** Cascade AI Assistant  
**Status:** Feasibility Analysis Complete - Pending Approval
