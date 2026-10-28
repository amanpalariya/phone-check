# Phone Check

Android notification mirroring, actions, replies, and dismissal, with a native macOS menu-bar companion. Both apps are in this repository. One phone, one Mac, same local network. No backend or accounts.

Local Wi-Fi remains the configured transport and the integration-test path. Firebase is the intended production default; both apps now include project-independent HTTPS real-time adapters behind the same notification interfaces. Project authentication, cloud pairing, session provisioning/reconnect and setup UI remain to be connected when the project exists. See [Firebase setup and architecture](firebase/README.md).

- `android/`: Kotlin, Compose, Material 3; Android 11+. System dynamic color on Android 12+, Material purple fallback on older versions.
- `macos/`: SwiftUI, Network, CryptoKit, UserNotifications; macOS 14+. Native Liquid Glass on macOS 26+, standard-material fallback on older versions.
- `protocol/`: wire format, authentication, and sync rules.

## Build

Android needs JDK 17+, Android SDK Platform 37.0, and Build Tools 36.0.0. Open `android/` in Android Studio or set `ANDROID_HOME` / `android/local.properties`:

```sh
cd android
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

APK: `android/app/build/outputs/apk/debug/app-debug.apk`.

For macOS, install Xcode or its command-line tools:

```sh
./scripts/build-macos.sh
open "macos/build/Phone Check.app"
```

The script makes an ad hoc signed local build. For reliable macOS local-network privacy identity and Keychain access across rebuilds, use an Apple-issued identity:

```sh
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-macos.sh
```

Open `macos/Package.swift` in Xcode to edit the Mac sources. Launch the packaged `.app`, rather than the bare Swift executable, so notification authorization has a bundle identity. Distribution signing and notarization are not configured.

Click the menu-bar icon to open a notification pane beneath the icon: separate glass cards over a softly fading desktop blur. Click the icon again, press Escape, or click outside to close it. Search, expanded groups and replies stay in the pane. The backdrop uses AppKit’s standard behind-window material; Liquid Glass is reserved for the cards. **Settings → Appearance… → Custom** retains the opposite-tone backdrop and live transparency adjustment; your choices are saved.

For local UI testing, open the Mac companion's settings menu and choose **Notification testbed…**.
Add any of the 16 sample types, or choose **Show all**. Expand samples to try actions and replies;
use **Update last**, **Remove last**, and **Action result** to exercise updates, removals, and failures.
Enable **Show in notification pane**, then click Phone Check in the menu bar to view and interact with
the same samples there. **Exit** returns the pane to the phone feed. Samples use installed
Messages, Mail, Safari, App Store, Music, FaceTime, Voice Memos, and Calendar icons with fictional content.
The testbed uses the real notification views with simulated phone responses, without pairing or system alerts.

```sh
./tests/ui/build-mac-review.sh
macos/build/PhoneCheckMaterialReview.app/Contents/MacOS/PhoneCheckMaterialReview --testbed-checks
macos/build/PhoneCheckMaterialReview.app/Contents/MacOS/PhoneCheckMaterialReview --pane-checks
# Compare native backdrop materials over a detailed background:
open -n macos/build/PhoneCheckMaterialReview.app --args --blur-review
# Actual pane over the same background (add --dark for dark appearance):
open -n macos/build/PhoneCheckMaterialReview.app --args --pane-blur-review
# Live panel preview with local samples:
open -n macos/build/PhoneCheckMaterialReview.app --args --pane
```

Core checks run without XCTest or a full Xcode install:

```sh
swift run --package-path macos PhoneCheckChecks
```

## Pair

1. Open the Mac companion from the menu bar and choose **Pair phone**.
2. Enter its pairing code in the Android app within five minutes. Both devices must be on the same private IPv4 LAN; choose the Mac's Wi-Fi address if several addresses appear. Guest Wi-Fi client isolation can prevent connections.
3. Grant Android notification access and, on Android 17+, local network access. Sideloaded builds may require **Allow restricted settings** in Android app settings before notification access can be enabled.
4. Enable Mac notifications in the companion. Allow local network access if macOS asks.

Existing phone notifications appear silently in the companion on each connection. Only live, changed notifications produce system alerts. While the phone screen is on and unlocked, notifications still sync but Mac banners are suppressed; locking the phone does not replay them. **Dismiss on phone** waits for phone confirmation. Clearing or timing out a Mac banner never dismisses the phone notification.

Unpair on both devices to replace a phone, replace a Mac, or change a Mac address after DHCP changes. Permission revocation disconnects syncing; restore access to resume. Device clocks must agree within roughly ten seconds for dismissal commands. Notification content comes only from Android's listener API: some apps, work profiles, private content, and non-dismissible notifications are restricted by the OS.

## Notification testbed

Open the Android overflow menu → **Notification testbed**. Post samples individually or together; use **Update** for progress and **Clear** to remove samples. Receipts show actual Android action execution, taps, replies, and removals.

Twenty scenarios cover text, expanded text, inbox, conversations, pictures, progress, groups, ongoing, buttons, media, calls, silent/private content, custom layouts, canceled intents, unlock-required actions, fixed choices, attachment-only and multiple-input actions. These are real Android notifications, including a short-lived foreground service for the call sample.

Mac rows show source icons, rich content, and original actions. Text replies and fixed choices use Android RemoteInput. **Open on phone** sends the original content intent. **Dismiss on phone** succeeds only after Android confirms removal; **Sent to phone** confirms intent dispatch, not the target app's business operation. Native Mac alerts expose up to three supported actions plus dismissal; the companion shows all captured actions (up to six).

Android can restrict background activity launches, locked-device actions, redacted content, and non-dismissible notices. Arbitrary Android RemoteViews cannot render on macOS; their standard text is shown. Attachment uploads and multiple-input actions remain phone-only. Picture previews are bounded; this is not photo transfer or call audio.

## Code organization

Android's bridge coordinates capture, asset conversion, command handling and a transport interface. Mac's companion coordinates active sync, a command controller, native alert delivery and SwiftUI rows. Models and cryptography live in PhoneCheckCore. Testbed fixtures are separate from production capture/dispatch logic. Active content and reply drafts stay in memory; there is no notification history.

## Verification

Run the [emulator integration suite](tests/emulator/README.md) to exercise the real Android listener against the Mac companion code. See [VALIDATION.md](VALIDATION.md) for checks actually run and the remaining physical-device checklist. Active notification text is kept in memory only; pairing material lives in macOS Keychain and Android Keystore-encrypted private preferences. Android backup and transfer exclude those preferences. No notification bodies or credentials are logged.

Build versions were checked against official SDK and Maven metadata on October 27, 2026. The checked-in Gradle wrapper pins the distribution checksum. See [Android build compatibility](https://developer.android.com/build/releases/gradle-plugin), [Compose BOM](https://developer.android.com/develop/ui/compose/bom), [local network permission](https://developer.android.com/privacy-and-security/local-network-permission), and [Apple local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
