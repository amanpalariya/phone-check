# Validation — October 27, 2026

## Run on this Mac

| Check | Result |
| --- | --- |
| Android `:app:assembleDebug` | Passed; debug APK produced |
| Android `:app:testDebugUnitTest` | Passed; 7 tests, 0 failures |
| Android `:app:lintDebug` | Passed; 0 errors, 10 warnings, 2 hints (tooling/resource/style suggestions) |
| SwiftUI macOS executable build | Debug and release passed with Swift 6.4, deployment target macOS 14 |
| `swift run --package-path macos PhoneCheckChecks` | Passed; 7 checks |
| Packaged `.app` / ad hoc signature | Built and signature verified |
| macOS application launch | Debug process started successfully; unauthenticated TCP probe closed without content |
| Native UI inspection | Installed Blip popover/settings inspected; Android pairing/permission screenshots reviewed; native Mac glass view reviewed over a varied backdrop in light/dark. Live popup capture remained unreliable. |
| Android 17 emulator UI test | Passed; real pairing form and both permission states |
| Android 17 emulator notification flow | Passed; real listener, encrypted transport, production Mac model |
| Rich notification integration | Passed; 7 tests covering 20 real notification scenarios, original intents, replies, icons, media/call controls, stale/duplicate commands and 60-image reconnect |
| Native Mac notification smoke | Passed; real text/image delivery, reply/action categories, reply handler, removal cleanup; 0 skips |
| Physical Android testing | Not run; no physical phone connected |

Android tests check shared Swift/JCA encryption and key-derivation vectors, directional keys, replay/tamper rejection, frame limits/truncation, and private-address/strong-key pairing validation. Mac checks cover silent snapshot replacement, duplicate updates, stale revision protection, disconnect reset, handshake proof binding, frame/JSON behavior, and replay/reordering/tamper/wrong-key rejection.

The full integration run used an isolated Pixel 7 AVD, Android 17 / API 37, AOSP ARM64 image revision 6, Android Emulator 37.2.12. All 10 instrumented tests passed: permission UI, baseline notification flow, the seven-test rich notification suite, and native Mac alerts. No tests were skipped. Reports and screenshots are generated under `android/app/build/reports/emulator/`; no test credentials remain after cleanup.

The rich suite verified source icons, adaptive Android launcher icons, packaged Mac icon presence, supported/unsupported input metadata, original PendingIntent button execution, original content-intent Activity launch, freeform and fixed-choice RemoteInput, media and short-service call controls, confirmed removal on both sides, progress updates, and complete image reconciliation after a snapshot exceeding 1 MiB. Canceled intents, stale/expired commands and duplicate side-effect prevention were exercised. The existing flow also covered authenticated pairing through the UI, phone-side removal, non-dismissible notices and listener access revocation/restoration.

Native Mac checks used the real UserNotifications center under an isolated test bundle. Text notifications and JPEG attachments were delivered, text-input/action categories registered, the production native reply handler dispatched RemoteInput to Android, and phone removal withdrew the delivered Mac copy. Routing into the native action handler is programmatic: OS banner buttons themselves were not clicked. Default Mac dismissal and banner timeout behavior is covered by category/delegate source review, not automated UI clicking.

The Mac host compiles production companion, alert delivery, command controller, transport and crypto sources. It has a separate bundle/Keychain identity. Android fixtures are real OS notifications from the app testbed and a separate test-only producer. Android permission-controller dialogs use ADB setup, not interactive verification. Native rich rows and the reply composer were visually/accessibility-tree reviewed in light/dark; the Android testbed screenshot was reviewed.

Physical-device Wi-Fi, macOS local-network privacy prompts, vendor power restrictions, locked physical phones, work-profile/OTP redaction and full accessibility acceptance remain unverified. Command-line Swift tools lack XCTest, so seven core checks use throwing assertions in a dedicated executable. The Android unit suite contains four crypto/wire checks and three command freshness/ledger checks.

## Physical-device acceptance checklist

Use a physical Android phone and Mac on the same private Wi-Fi. Build/install the APK and launch the packaged Mac `.app` with a stable Apple signing identity for local-network privacy testing.

- [ ] Before pairing, post a phone notification: no text reaches the Mac.
- [ ] Start pairing; test malformed code, wrong secret, expired code, and a second phone. Only the intended phone pairs.
- [ ] Deny notification access: show the access action, forward nothing. Grant access: current set appears silently.
- [ ] On Android 17+, deny then grant local-network permission; also test permanent denial and Settings recovery.
- [ ] Grant Mac local-network access; deny/revoke it and verify the connection stops and retry recovers after access is restored.
- [ ] Deny then enable Mac notification permission. Active list still works; system alerts appear only when authorized.
- [ ] Post a text notification; verify app, title, body, and a single Mac system alert.
- [ ] Update it repeatedly; verify one active entry and one alert identifier, with no duplicate alert for identical content.
- [ ] Choose **Dismiss on phone** from the companion and from a system alert. Keep pending until Android removes it; verify removal on both devices.
- [ ] Dismiss directly on the phone; verify the Mac entry and delivered alert clear.
- [ ] Dismiss a Mac alert normally; verify the phone notification remains. Let a banner time out and repeat.
- [ ] Try a non-dismissible notification; no phone dismissal action should be offered.
- [ ] Update a notification just before dismissal; stale revision must not dismiss the new content.
- [ ] Disconnect with a dismissal pending; verify no success is reported and no old command executes on reconnect.
- [ ] Disconnect Wi-Fi, sleep/wake the Mac, and restart each app; verify a silent replacement snapshot, no old alert replay, and updates/removals continue.
- [ ] Revoke Android notification access while connected; verify the Mac clears and forwarding stops. Restore access and reconcile.
- [ ] Test redacted/OTP content and a work profile; mirror only what the listener actually receives.
- [ ] Unpair on both sides; verify credentials are removed and the previous pairing code no longer connects.
- [ ] Exercise all testbed styles with real third-party apps, especially locked-phone actions, content intents and replies.
- [ ] Test dark appearance, large Android text, TalkBack, keyboard navigation, and VoiceOver.
- [ ] Test overnight/Doze reconnection on the intended phone vendor; record any OS delays.

## Native theme review

- Android uses Material 3 color roles, type scale, standard field/button styling, and wallpaper-based dynamic colors on Android 12+. Older versions use the Material purple fallback. The revised screens were built, linted, exercised by UI Automator, and visually reviewed on the API 37 emulator.
- macOS uses a transparent menu-bar utility window with SwiftUI `glassEffect(.regular)` and native `.glassProminent` primary controls on macOS 26+, with standard-material/native-button fallbacks on macOS 14–15. No glass effect is drawn over individual notification rows.
- `tests/ui/build-mac-review.sh` builds an isolated, visual-only native review app. It uses the production popup view on a varied backdrop in light and dark appearances. It does not connect, access Keychain, or request permissions.
- Native review and source inspection do not certify every HIG or accessibility requirement. VoiceOver, increased contrast, reduced transparency/motion, keyboard behavior across all popup states, and actual desktop compositing remain separate acceptance checks. Capture of the live transient utility window was unreliable, so visual review of that surface used the controlled native review window.

References checked October 27, 2026: [Apple Liquid Glass adoption](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Apple materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials), and [Android Material 3](https://developer.android.com/develop/ui/compose/designsystems/material3).

Run the visual review app with `--rich` to inspect production rich rows and reply controls in light and dark appearances using synthetic content.
