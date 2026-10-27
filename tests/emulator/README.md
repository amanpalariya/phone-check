# Android Emulator integration tests

These tests use a real Android `NotificationListenerService` and the production Swift `Companion`, `FramedConnection`, and crypto code. A separate Mac `.app` bundle isolates Keychain items and notification-center state from Phone Check. No production pairing is read or changed.

Use a **dedicated emulator**: the runner clears Phone Check's app data and changes its permission state there. It refuses physical-device serials. Quit the normal Mac companion first because the test host uses the same port, 47831.

## Setup

Requires macOS, Swift command-line tools, JDK 17+, Android SDK, and Python 3. Set `JAVA_HOME` and `ANDROID_HOME`; put `adb` and SDK command-line tools on `PATH`.

```sh
sdkmanager 'emulator' 'system-images;android-37.0;default;arm64-v8a'
avdmanager create avd --name PhoneCheck_Testbed_API37 --package 'system-images;android-37.0;default;arm64-v8a' --device pixel_7 </dev/null
emulator -avd PhoneCheck_Testbed_API37 -no-snapshot -no-audio
```

The ARM64 image is for Apple Silicon. Wait for boot, then from the repository root:

```sh
python3 tests/emulator/run.py --serial emulator-5554
```

`--skip-build` reuses existing APKs and the Mac test-host bundle. The runner installs the main app, its instrumentation APK, and `notification-fixture`, a separate test-only notification producer. The fixture receiver requires shell's `DUMP` permission and is never included in the main APK.

Add `--native-alerts` to request notification authorization for the isolated Mac test app and check real native delivery, image attachments, registered reply/action categories, and cleanup. Authorization is a system permission; if it is not granted, that optional check reports a skip. `--suite RichNotificationTest` selects the rich interaction suite.

## Coverage

- Pairing UI, notification-access explanation, and Android 17 local-network-access state.
- Real authenticated Android-to-Mac transport and initial active-state snapshot.
- Posting and updating the same Android notification without duplicate active entries.
- Calling the production Mac dismissal method; checking both Mac state and Android's actual active notifications for confirmed removal.
- Phone-side removal clearing Mac state.
- A new authenticated connection and snapshot after reconnect, with subsequent removal still working.
- Non-clearable notification metadata and refusal to dismiss it.
- Notification-listener access revocation disconnecting the Mac, and restoration reconciling an empty set.

The rich suite posts all 20 in-app scenarios, checks source icons and adaptive launcher icons, executes original action/content intents, freeform/fixed-choice replies, media/call controls, stale/canceled/expired intents, duplicate-command rejection, updates and confirmed dismissal. It also reconnects with 60 picture notifications exceeding one frame and verifies complete snapshot reconciliation. Native action routing calls the production notification delegate handler; OS banner buttons themselves are not clicked by automation. Runtime permission grants use ADB test setup; Android permission-controller dialogs are not validated. Hardware Wi-Fi isolation, macOS local-network privacy, Doze/vendor behavior, redaction, and accessibility still require separate checks.

Test-only pairing codes are transferred through a private temporary directory and the emulator app's private files, never process arguments or logs. Test Mac Keychain items and emulator pairing data are removed in cleanup. Screenshots contain only synthetic pairing/permission/testbed states and are saved in `android/app/build/reports/emulator/`.

The control server binds only to host loopback on port 47832. Android reaches it and the Mac transport through the emulator host alias `10.0.2.2`. See [Android Emulator networking](https://developer.android.com/studio/run/emulator-networking).
