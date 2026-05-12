# MFA Requirements (MFA Locker Requirements)

Source: https://www.notion.so/adguard/2d1aa56b77308000bfe2c028f389cc31

---

## 1. Terms and States

**Locker** — an encrypted file (or set of files) containing entries and an integrity check (HMAC).

**Session (Unlocked session)** — the state after a successful password/biometric entry, where the list of metadata (EntryMeta) is available in memory until auto-lock.

**EntryMeta (metadata)** — only the entry metadata is available in decrypted form (e.g., the wallet name/label, public key).

**EntryValue (secret)** — the secret part of an entry. The value is extracted and shown only on an explicit request and lives for the minimum possible time.

**EntryInput** — abstract base class for entry operation bundles. Contains optional fields: metadata (EntryMeta), secret (EntryValue), and entry identifier (EntryId). Implements `Erasable` with shared `isErased`/`erase()` logic. Subclasses narrow required fields for specific operations.

**EntryAddInput** (extends EntryInput) — a bundle of entry data for adding entries: required metadata (EntryMeta), a required secret (EntryValue), and an optional explicit entry identifier (EntryId). Used when initializing storage with one or more entries or when adding a new entry.

**EntryUpdateInput** (extends EntryInput) — a bundle of update data for an existing entry: a required entry identifier (EntryId), optional new metadata (EntryMeta), and an optional new value (EntryValue). At least one of metadata or value must be provided.

**Application states:**

- `No storage` — no storage exists (first launch / after wipe / after reset when the last entry is deleted).
- `Locked` — storage exists but is locked.
- `Unlocked` — active session, keys cached in memory.

---

## 2. Storage Initialization (Password Creation)

### 2.1. General Requirements

- The user sets a password (see password policy below).
- After the password is set successfully, the storage is created. Initialization accepts a list of zero or more initial entries (`List<EntryAddInput>`); the storage can be created with an empty entries list or with multiple entries at once.
- The storage must have an integrity check mechanism (HMAC) and a password correctness check.

### 2.2. Initialization Mode

**A) Immediate (non-deferred)**

- Immediately after entering the password, the storage is created. Initialization may include zero, one, or multiple initial entries provided as a list of `EntryAddInput` objects.
- The storage is then saved (including HMAC).

### 2.3. Default Auto-Lock Timeout

The default lock timeout is **10 minutes**.

---

## 3. Unlocking (Login / Unlock)

### 3.1. Password Unlock

- The user enters the password.
- If the password is incorrect or the integrity check (HMAC) fails:
  - Show an error (without details about what specifically failed: password or integrity).
  - Limit input attempts to **100 per hour**.
- On successful unlock:
  - Only public keys and wallet names are cached in memory until auto or manual lock. The seed phrase and private key enter memory only at the moment of signing a transaction or displaying the seed phrase during wallet import, and are immediately wiped afterward.
  - The application transitions to the `Unlocked` state.

### 3.2. Key List (after Unlock)

- Only `EntryMeta` (metadata) is available in decrypted form.
- Values (`EntryValue`) are not extracted automatically and must not appear in logs/analytics.
- The public key must also not appear in logs/analytics.

### 3.3. Reading a Value (View secret)

- When requesting a value: if the session is inactive (`Locked`) → request the password/biometric again.
- If the entry is not found, an error is thrown.
- When a value is requested, the secret is shown in a temporary state:
  - stored in memory for the minimum possible time,
  - automatically wiped after use (screen closed, timeout, copy completed, etc.).

---

## 4. Entry Management

### 4.1. Adding an Entry

- Entry data is provided as an `EntryAddInput` (required metadata, required secret, optional explicit `EntryId`).
- If no `EntryId` is provided, a UUID is auto-generated.
- If an entry with the resolved ID already exists, the operation is rejected with a `duplicateEntry` error.
- Every change goes through:
  - file overwrite (atomic write),
  - HMAC update.
- Password/biometric input is required.

### 4.2. Updating an Entry

- Update data is provided as an `EntryUpdateInput` (required `EntryId`, optional new metadata, optional new value). At least one of metadata or value must be supplied. When value is `null`, the current value is left unchanged.
- Every change goes through:
  - file overwrite (atomic write),
  - HMAC update.
- Password/biometric input is required.

### 4.3. Deleting an Entry

- Explicit confirmation is required.
- After deletion:
  - the file is fully rewritten with the new list.
  - the one entry is removed from the cache.
- Password/biometric input is required.

### 4.4. Deleting the Last Entry → Password Reset

- If the last entry is deleted — the password must be reset.
- If the number of entries after deletion reaches 0:
  - the storage transitions to the `No storage` state (the password must be set again),
  - the password wrapper and Locker state are deleted/reset,
  - further access is only possible through a new initialization.
  - The entire storage file is deleted.

### 4.5. Wiping Everything (Danger Zone / Wipe)

- After fully uninstalling the application:
  - The storage file is fully deleted and the Locker state is reset.
  - After wipe, the application is in the `No storage` state.
- This action does **not require** password/biometric input.

---

## 5. Changing the Password

- Allowed only during an active session (`Unlocked`).
- To change the password, the user must confirm by entering the **old password** (biometrics are not accepted).
- During the change:
  - the old wrapper for `Origin.pwd` is deleted,
  - a new one is created,
  - entries remain unchanged.
- Access to entries is now only via the new password.

---

## 6. Biometrics

### 6.1. Enabling/Disabling Biometrics

- Enabling/disabling is only possible during an active session (`Unlocked`) and when supported by the platform.
- When enabling:
  - a wrap/key associated with `Origin.bio` is created (without compromising the master key).
  - biometric authentication must be requested; access is enabled only upon successful authentication.
- When disabling:
  - the wrap for `Origin.bio` is deleted.

### 6.2. Biometric Class (Android)

- The application must work only with `BIOMETRIC_STRONG`.

### 6.3. Neutral Prompt Texts (Android)

Since it is often impossible to reliably determine "fingerprint vs. face" on Android, prompts must be neutral:

- "Confirm biometrics"
- "Use biometric authentication"

Do not write "Place your finger" if face unlock may be used.

---

## 7. Biometrics Changed in Device Settings

- If biometrics are changed on the device: do not allow biometric login, disable biometrics, and ask for the password.
- Display a notification that biometrics need to be re-enabled.

---

## 8. Auto-Lock and Focus-Loss Behavior

- The application **must not** lock instantly on brief focus loss.
- Locking rules:
  - if the device is locked (lock screen) → lock immediately,
  - if the application is in the background for more than timeout minutes → lock,
  - if the application is active but the user has not interacted for more than timeout minutes → lock.
- The timeout is configurable in settings.
- Timeout options:
  - 1 minute
  - 5 minutes
  - 30 minutes
  - 1 hour
  - 3 hours
  - 6 hours

---

## 9. Screenshots

- Screenshots on screens where the password has been entered are **prohibited**.
- On screens with password input and/or secret display, enable screenshot/screen recording protection (platform-specific).
- If preventing screenshots is not possible — at least warn the user.

---

## 10. Password Field When the App Is Minimized

**Case:** the user has entered the password but has not pressed Continue → minimized the app → returned → the password is still in the field.

**Requirements:**

- Clear the field after **5 minutes** of being minimized (same timer as the background lock).
- Security considerations:
  - the password must not appear in the task switcher preview (the screen must be obscured/protected when minimized),
  - the password must not appear in logs/analytics,
  - the password must not appear in OS autofill suggestions unless explicitly allowed by a setting.

---

## 11. Password Autofill

- Autofill is allowed.
- Consequence: the auto-lock on focus loss must not interfere with "split-second" switches.
- The grace period / no-instant-lock rule is a **mandatory dependency** for a comfortable autofill experience.

---

## 12. Password Policy and Validation

- Minimum **8 characters**.
- At least **1 digit** required.
- At least **1 uppercase letter** required.
- Allowed characters — Latin letters, digits, standard special characters:

```
A–Z, a–z, 0–9
! @ # $ % ^ & * ( )
- _ = +
{ }
\ |
; : ' "
, . < >
/ ?
```

---

## Password and Biometric Flow

### 1. Storage Creation and Initialization

- When creating or importing the first wallet, the application requires the user to set a password.
- The user enters: a password and a password confirmation.
- After the password is set successfully, the application offers to enable biometrics if available on the device.
- After the password is set, the storage (Locker) is created. One or more initial entries can be written at initialization time via the `EntryAddInput` list (e.g., the seed phrase of the first wallet). The list may also be empty if no entries are available yet. Each entry requires both metadata and a secret.

### 2. Using the Seed Phrase and Secrets

Secrets (seed phrase, private keys) are extracted from storage only when necessary, in the following scenarios:

- sending a transaction (send)
- sending a transaction (swap)
- sending a transaction (approve)
- sending a transaction (revoke)
- viewing the seed phrase
- importing a new wallet
- creating a new wallet

**EntryValue (secret) requirements:**

- decrypted only for the duration of the operation,
- stored in memory for the minimum possible time,
- must be deleted from memory immediately after use.

Each such action requires: entering the password or using biometrics (if enrolled). Password and biometrics are considered equivalent.

If biometric authentication is unavailable or failed — fallback to password entry is mandatory.

### 3. Password Entry in Other Scenarios

#### 3.1. Logging Into the Application

To unlock the application when the storage is in the `Locked` state.

#### 3.2. Application Auto-Lock

The application automatically transitions to the `Locked` state when:

- the user is inactive for X minutes or the application has been in the background for more than X minutes (X is user-configurable),
- the device is locked,
- the device is powered off,
- device security settings change (e.g., biometrics are removed).

### 4. Operations Where Only the Password Is Used

In the following scenarios biometrics are **not permitted** and the password is exclusively required:

- enabling or disabling biometrics,
- changing the password.

### 5. Operations Requiring Confirmation

**Wallet deletion:**
- deleting any wallet must be confirmed with the password or biometrics (if enrolled).

**Changing security settings:**
- e.g., changing the auto-lock timeout,
- requires confirmation (password or biometrics).

### 6. Forgotten or Lost Password

- A forgotten or lost password **cannot be recovered**.
- The only way to regain access is to go through the "Forgot password" flow.
- As part of this flow:
  - all added wallets are deleted,
  - the storage is fully deleted,
  - the password is reset.
- After the flow completes, the application returns to the `No storage` state.
