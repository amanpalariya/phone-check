# Phone Check

Android notification mirroring, actions, replies, dismissal, and phone battery/charging/Battery Saver status, with a native macOS menu-bar companion. Both apps are in this repository. One phone, one Mac, with explicit encrypted pairing and optional Google sign-in.

Without signing in, pair directly on the same local network. For signed-in pairs, Firebase Realtime Database handles pairing and initial address discovery. The apps automatically switch to an authenticated, encrypted local connection when reachable, stop Firebase sync while local, and fall back to Firebase when the local link fails. The project uses Spark, with pairing and session authorization implemented through database rules and device-held encryption secrets. See [Firebase setup and architecture](firebase/README.md).

- `android/`: Kotlin, Compose, Material 3; Android 11+. System dynamic color on Android 12+, Material purple fallback on older versions.
- `macos/`: SwiftUI, Network, CryptoKit, UserNotifications; macOS 14+. Native Liquid Glass on macOS 26+, standard-material fallback on older versions.
- `protocol/`: wire format, authentication, and sync rules.

## Build

The shared icon artwork is `assets/app-icon.png`. After replacing it, run
`swift scripts/make-app-icons.swift` from the repository root to regenerate the
Mac icon and Android adaptive foreground. Android also has a simplified vector
for system-themed icons.

Supply the gitignored `android/app/google-services.json` and `macos/GoogleService-Info.plist` from Firebase project settings, including Google OAuth client IDs and the database URL. The Mac also needs `macos/GoogleOAuthClient.json`, downloaded for the project's Desktop OAuth client.

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

Both platforms default to **development** (`debug`): Android Studio's debug variant, bare `./gradlew` in `android/`, and the Mac build script. Development builds include the notification testbed and Advanced settings. Release builds exclude the testbed, its fixtures, and its Advanced settings entry.

Mac development pairing is stored as unencrypted JSON in `~/Library/Application Support/dev.phonecheck.mac.pairing.development/pairing.json`, inside an owner-only directory (0700) with an owner-only file (0600). It survives rebuilding/re-signing without using Keychain for the pairing secret. Mac development Google sign-in stores its Firebase refresh token and cached profile as unencrypted JSON in `~/Library/Application Support/dev.phonecheck.mac.firebase.development/session.json`, also inside an owner-only directory (0700) with an owner-only file (0600). Sign-out removes the session file. Development never accesses Keychain, including old development entries; after updating from a Keychain-backed development build, sign in once again. Release pairing and Google sessions remain in Keychain. Development never reads, migrates, or clears release credentials, so switching build configurations requires pairing and signing in separately. Android continues using Keystore-encrypted private preferences in both variants.

Build a release explicitly:

```sh
CONFIGURATION=release ./scripts/build-macos.sh
cd android
./gradlew :app:assembleRelease
```

The Mac script writes either configuration to `macos/build/Phone Check.app`; rebuild with no configuration to return to development. Android release output is `android/app/build/outputs/apk/release/app-release-unsigned.apk`; release signing is not configured.

The Mac script makes an ad hoc signed local build. For a stable macOS local-network privacy identity, or reliable release Keychain access across rebuilds, use an Apple-issued identity:

```sh
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-macos.sh
```

Open `macos/Package.swift` in Xcode to edit the Mac sources. Launch the packaged `.app`, rather than the bare Swift executable, so notification authorization has a bundle identity. Distribution signing and notarization are not configured.

The menu-bar icon outlines the app artwork and shows a dot for unchecked live notification changes. Opening the pane clears the dot; automatic previews do not mark notifications as checked. Click the menu-bar icon to open a notification pane beneath the icon: separate glass cards over a softly fading desktop blur. Click the icon again, press Escape, or click outside to close it. Search, expanded groups and replies stay in the pane. The title and search share a notification-style card near the menu bar. The backdrop uses a blur-only compositor renderer with a standard-material fallback; Liquid Glass is reserved for the cards. The soft backdrop follows the visible content and stays dark in both light and dark mode. A bottom fade signals more notifications below and disappears at the end. Blur and backdrop strength use fixed defaults without appearance controls. The blur-only path uses undocumented macOS compositor APIs on supported OS generations.

In a development build, open **Settings → Advanced → Notification testbed → Open…** on the Mac.
Add any of the 16 sample types, or choose **Show all**. Expand samples to try actions and replies;
use **Update last**, **Remove last**, and **Action result** to exercise updates, removals, and failures.
Enable **Show in notification pane**, then click Phone Check in the menu bar to view and interact with
the same samples there. **Send preview** and **Send 3** show timed previews beneath the menu-bar icon, using simulated phone actions and bypassing Focus for testing. **Exit** returns the pane to the phone feed. Samples use installed
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
# Pane over a scrollable text pattern (add --dark for dark cards):
open macos/build/PhoneCheckMaterialReview.app --args --pane-blur-review --scroll-through-review --more
# Live panel preview with local samples:
open -n macos/build/PhoneCheckMaterialReview.app --args --pane
# Preview welcome and QR pairing surfaces (add --dark for dark appearance):
open -n macos/build/PhoneCheckMaterialReview.app --args --pairing-review
```

Add `--single` (without `--more`) to check short-list alignment, or `--no-backdrop-tint` to inspect blur independently of the dark wash. The fixed defaults use blur 1 with a 2.5% dark wash in light mode and 3.5% in dark mode.

For backdrop review, keep one preview instance open and inspect a composed-screen capture using macOS Screenshot. Window-only captures omit the content behind the panel. Scrolling over exposed backdrop must leave the underlying pattern's scroll position unchanged; the notification list must still scroll normally. The scroll fixture records its underlying offset in `/tmp/phonecheck-behind-scroll-offset`.

Development credential storage and core checks run without XCTest or a full Xcode install:

```sh
./tests/ui/check-credentials.sh
swift run --package-path macos PhoneCheckChecks
```

Check that the Mac’s rendered pairing QR decodes correctly in both appearances:

```sh
swiftc -parse-as-library macos/Sources/PhoneCheck/PairingQRCode.swift tests/ui/PairingQRCodeChecks.swift -o /tmp/phonecheck-qr-checks
/tmp/phonecheck-qr-checks
```

## Pair

1. For local-only sync, leave the Mac signed out and connect both devices to the same network. For cloud fallback, sign in with the same Google account on both devices before pairing. Click the Mac menu-bar icon and choose **Pair phone**; the code expires in five minutes.
2. Tap **Scan QR code** on Android, or use **Enter code instead** and **Copy code** on Mac. Local pairing needs no account or internet connection; cloud pairing can use different networks.
3. Grant Android notification access and local-network access for local-only pairs. Sideloaded builds may require **Allow restricted settings** in Android app settings before notification access can be enabled.
4. Enable notification previews in **Settings → General**, granting Focus access so previews stay quiet during Focus. Settings on both apps includes the Google account and device connection, with explicit sign-out/unpair confirmations. Development builds also include **Advanced** with the notification testbed.

Scanning uses [Google code scanner](https://developers.google.com/ml-kit/vision/barcode-scanning/code-scanner), which processes images on-device without granting Phone Check camera access. It requires Google Play services and may need an initial scanner download; manual entry works without it. The QR code contains the same temporary pairing secret as the copied code and expires or is canceled with it.

Sync is owned by Android's system-bound notification listener and continues when the app is in the background or its display is off. The listener recovers automatically when networking returns or Doze ends. Android's system/OEM power restrictions can still defer network access. No additional background settings are added. The Mac stays available while running with its pane closed, pauses syncing during system sleep, and establishes a fresh session after waking. A Wi-Fi or cloud icon beside the Mac settings control shows the active connection; a slashed icon indicates it is disconnected.

Existing phone notifications appear silently in the companion on each connection. Only live, changed audible notifications produce temporary previews beneath the menu-bar icon, with the originating app icon; nothing is posted to macOS Notification Center. Previews share the list’s collapsed-row sizing, glass surface, and dark backdrop. Up to three previews appear together, with a link to the full list for larger bursts. Each expires after six seconds (paused while hovered); use the shared up arrow to hide the whole stack, while the hover cross sends **Dismiss on phone** and keeps it visible until removal is confirmed. Previews stay hidden while Focus is active or unavailable. Older Android peers without sound metadata mirror silently until updated. While the phone screen is on and unlocked, notifications still sync but Mac previews are suppressed; locking the phone does not replay them. **Dismiss on phone** waits for phone confirmation. Hiding or timing out a Mac preview never dismisses the phone notification. Android supplies each notification’s DND allowance, so allowed app/conversation exceptions can still preview; blocked notifications mirror silently.

Unpair on both devices to replace a phone, replace a Mac, or change a Mac address after DHCP changes. Permission revocation disconnects syncing; restore access to resume. Device clocks must agree within roughly ten seconds for dismissal commands. Notification content comes only from Android's listener API: some apps, work profiles, private content, and non-dismissible notifications are restricted by the OS.

## Notification testbed

In an Android development build, open **Settings → Advanced → Notification testbed**. Post samples individually or together; use **Update** for progress and **Clear** to remove samples. Receipts show actual Android action execution, taps, replies, and removals. To test Mac previews, use **Post preview in 7s**, close the Mac list, and lock the phone before it arrives. This removes the previous Basic sample first so only-alert-once does not suppress the new test; immediate samples posted while the phone is unlocked mirror without a preview.

Twenty-one scenarios cover text, expanded text, inbox, conversations, pictures, progress, groups, ongoing, buttons, media, calls, silent/private content, custom layouts, canceled intents, unlock-required actions, fixed choices, attachment-only and multiple-input actions. These are real Android notifications, including a short-lived foreground service for the call sample.

Media players live inside the Mac panel header, above search, with artwork, track/artist, elapsed time, and circular playback controls. Switch between players when several apps have media notifications. They do not appear as notification rows, set the menu-bar new-notification dot, or generate song-change banners. Playback stays available while searching notifications.

Android reads the exact `MediaSession` token attached to each notification. Supported `PlaybackState` controls drive play/pause, previous/next, rewind/fast-forward, stop, and custom session actions; metadata/state callbacks update the Mac even without a notification repost. Standard controls use native Mac symbols, while custom/legacy controls retain Android's supplied icons and accessible labels, including localized labels. Apps without a usable session state fall back to their original notification PendingIntents; unsupported controls are never invented. The timeline supports dragging, keyboard and accessibility seeking when the session advertises `ACTION_SEEK_TO` and a known duration; otherwise it remains a progress display. Media commands validate stable per-action capabilities rather than volatile notification presentation revisions. Only bounded artwork is mirrored; no audio is transported.

The Android testbed includes a real session whose controls update state/track metadata without reposting, and a legacy player with Spanish labels and original icons.

Mac rows show source icons, rich content, and original actions. Text replies and fixed choices use Android RemoteInput. **Open on phone** sends the original content intent. **Dismiss on phone** succeeds only after Android confirms removal; **Sent to phone** confirms intent dispatch, not the target app's business operation. Clicking preview content crossfades into the companion. The chevron expands or collapses the preview in place, including its captured actions; taller content scrolls within the available display height. The companion shows all captured actions (up to six).

Android can restrict background activity launches, locked-device actions, redacted content, and non-dismissible notices. Arbitrary Android RemoteViews cannot render on macOS; their standard text is shown. Attachment uploads and multiple-input actions remain phone-only. Picture previews are bounded; this is not photo transfer or call audio.

## Code organization

Android's bridge coordinates capture, asset conversion, command handling and a transport interface. Mac's companion coordinates active sync, a command controller, transient menu-bar previews and SwiftUI rows. Models and cryptography live in PhoneCheckCore. Testbed fixtures are separate from production capture/dispatch logic. Active content and reply drafts stay in memory; there is no notification history.

## Verification

`./tests/local/check-unsigned-local.sh` exercises signed-out pairing and encrypted TCP sync
against the production Mac companion with a simulated phone on loopback. It uses an isolated
app identity and no cloud configuration on isolated port 47833. Add `--lifecycle-only`
to check sleep/wake, route state and background activity using a simulated transport. This does not replace
physical Android verification.


Run the [emulator integration suite](tests/emulator/README.md) to exercise the real Android listener against the Mac companion code. See [VALIDATION.md](VALIDATION.md) for checks actually run and the remaining physical-device checklist. Active notification text is kept in memory only; pairing material lives in macOS Keychain for release builds, the owner-only local file described above for Mac development builds, and Android Keystore-encrypted private preferences. Android backup and transfer exclude those preferences. No notification bodies or credentials are logged.

Build versions were checked against official SDK and Maven metadata on October 27, 2026. The checked-in Gradle wrapper pins the distribution checksum. See [Android build compatibility](https://developer.android.com/build/releases/gradle-plugin), [Compose BOM](https://developer.android.com/develop/ui/compose/bom), [local network permission](https://developer.android.com/privacy-and-security/local-network-permission), and [Apple local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
