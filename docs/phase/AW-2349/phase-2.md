# Iteration 2: Android — `ScreenLockStreamHandler`

**Goal:** Detect `ACTION_SCREEN_OFF` via `BroadcastReceiver` and push events through EventChannel.

## Context

Iteration 1 wired the Dart-side `EventChannel("biometric_cipher/screen_lock")`. This iteration provides the Android native implementation that pushes events through it.

Key design points:
- `ACTION_SCREEN_OFF` fires synchronously when the screen turns off — no polling, no latency.
- Must be registered with **application context** (not activity context) — the activity may not exist when the screen turns off.
- `ACTION_SCREEN_OFF` is a **protected broadcast** — manifest registration is not supported, only dynamic `registerReceiver()`.
- EventChannel lifecycle: register receiver in `onListen`, unregister in `onCancel`.
- References are stored as class fields and nullified in `onDetachedFromEngine` to prevent leaks.

## Tasks

- [x] **2.1** Create `ScreenLockStreamHandler`
  - File: new — `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/handlers/ScreenLockStreamHandler.kt`
  - `BroadcastReceiver` for `ACTION_SCREEN_OFF`, registered with application context
  - `onListen`: register receiver, `onCancel`: unregister receiver

- [x] **2.2** Register EventChannel in `BiometricCipherPlugin.onAttachedToEngine`
  - File: `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/BiometricCipherPlugin.kt`
  - Create `EventChannel("biometric_cipher/screen_lock")`, set stream handler
  - Store references as class fields (`screenLockEventChannel`, `screenLockStreamHandler`)

- [x] **2.3** Clean up in `onDetachedFromEngine`
  - Same file — `screenLockEventChannel?.setStreamHandler(null)`, nullify both references

## Acceptance Criteria

**Verify:** `cd example && fvm flutter build apk --debug`

## Dependencies

- Iteration 1 complete (Dart-side EventChannel wired)

## Technical Details

### `ScreenLockStreamHandler.kt` (new file)

```kotlin
package com.adguard.cryptowallet.biometric_cipher.handlers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.plugin.common.EventChannel

class ScreenLockStreamHandler(
    private val applicationContext: Context,
) : EventChannel.StreamHandler {

    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val screenOffReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                    events?.success(true)
                }
            }
        }

        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        applicationContext.registerReceiver(screenOffReceiver, filter)
        receiver = screenOffReceiver
    }

    override fun onCancel(arguments: Any?) {
        receiver?.let { applicationContext.unregisterReceiver(it) }
        receiver = null
    }
}
```

### Changes to `BiometricCipherPlugin.kt`

Add imports:
```kotlin
import io.flutter.plugin.common.EventChannel
import com.adguard.cryptowallet.biometric_cipher.handlers.ScreenLockStreamHandler
```

Add class fields:
```kotlin
private var screenLockEventChannel: EventChannel? = null
private var screenLockStreamHandler: ScreenLockStreamHandler? = null
```

In `onAttachedToEngine` (after existing `secureMethodCallHandler.startListening()`):
```kotlin
val streamHandler = ScreenLockStreamHandler(flutterPluginBinding.applicationContext)
val eventChannel = EventChannel(
    flutterPluginBinding.binaryMessenger,
    "biometric_cipher/screen_lock",
)
eventChannel.setStreamHandler(streamHandler)
screenLockEventChannel = eventChannel
screenLockStreamHandler = streamHandler
```

In `onDetachedFromEngine`:
```kotlin
screenLockEventChannel?.setStreamHandler(null)
screenLockEventChannel = null
screenLockStreamHandler = null
```

## Implementation Notes

- The handler directory `…/handlers/` is new — create it alongside the file.
- No new Gradle dependencies required; `EventChannel` and `BroadcastReceiver` are in the existing SDK.
- The `screenLockStreamHandler` field is stored but not otherwise used after setup; keeping the reference prevents premature GC and makes cleanup explicit.
