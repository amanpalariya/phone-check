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

The visual review app opens production rich rows and reply controls in light and dark appearances using synthetic content. Pass `--setup` to inspect the pairing surface instead.

## Notification cards — October 28, 2026

- Rounded material cards with spacing, a hover/focus close button, and left/right mouse-drag and trackpad swipe dismissal. All entry points use the existing confirmed phone-dismissal command; pending and non-dismissible notices cannot be dismissed again.
- SwiftUI app and isolated material review app built successfully; all seven core checks passed. Rounded cards were visually reviewed in light/dark, and the hover close button appeared during a mouse drag in the isolated review app. Physical trackpad and paired-phone acceptance remain to be checked.
- Follow-up: removed the visible open/dismiss labels, non-dismissible label, and ongoing pin. Clicking notification content invokes its original phone content action when available; reply, expansion, and original action controls remain separate. Mouse swipes take priority over opening. Rebuilt the Mac app and review app, reran all seven core checks, reviewed the cleaner cards in light/dark, and clicked Reply to verify the composer still opens. End-to-end opening/dismissal on a paired phone was not rerun.

## Transport preparation and smart alerts — October 28, 2026

- Notification transport selection is separate from capture, active-state reconciliation and
  command execution. Mac LAN and Firebase sessions share `NotificationConnection`; Android
  uses a factory with explicit local-network requirements. LAN remains configured by default.
- Added project-independent Firebase RTDB HTTPS/SSE clients and encrypted, bounded,
  acknowledged mailboxes on both platforms. Added an undeployed deny-by-default rules template
  and the remaining project/auth/pairing/session/cleanup/wake-delivery work in `firebase/README.md`.
- Added screen-on/unlocked attention samples on live posts and screen/unlock transitions.
  Mac suppresses alerts while keeping mirrored content; queued foreground presentation also
  checks current attention. Locking never replays suppressed alerts. Reconnect snapshots stay silent.
- Ran `swift build --package-path macos --product PhoneCheck` successfully. Ran the seven
  existing core checks and six new Firebase/attention check groups successfully. Checks cover
  ordered duplex delivery, duplicate suppression, queue bounds, invalid ACKs, server write
  failures, expiry, tampering, session isolation, SSE framing/revocation, endpoint configuration,
  activity freshness/order and a shared Swift/JVM encrypted-frame fixture.
- Ran Android `:app:assembleDebug`, `:app:testDebugUnitTest`, `:app:lintDebug` and
  `:app:assembleDebugAndroidTest` successfully with the existing JDK 17.0.21 toolchain.
  All 11 JVM tests passed. JSON-Java 20260814 is test-only; its version was checked against
  Maven Central metadata. No production Firebase SDK dependency or credentials were added.
- Updated the optional native-alert instrumentation test to put the emulator to sleep while
  testing banner delivery and restore it afterward. Built this instrumentation APK; did not
  execute the emulator/native-alert suite in this change. No emulator was connected, and an
  existing Mac companion was listening on the test suite's required port; it was left running.
- No Firebase project, cloud authentication, deployed rules, live stream, or physical-device
  validation was available. The rule file was checked as JSON, not executed against Firebase.
  Current checks do not establish Doze, push wakeup, network/token expiry or delivery latency.

Additional device checks:

- [ ] While the phone is awake and unlocked, post/update notifications: the Mac list updates
  without a new banner. Lock it: subsequent live posts may alert; earlier suppressed posts do not.
- [ ] Unlock while a Mac alert is queued: pending/foreground presentation respects the latest
  attention signal. Disconnect/reconnect and verify silent reconciliation and a fresh signal.
- [ ] After provisioning Firebase, validate the role/expiry/size rules in its emulator and on the
  project, then repeat the existing pairing, permission, action, reply, dismissal and reconnect
  checks over Firebase, including session rotation, unpair/revocation cleanup and token refresh.

## macOS notification testbed — October 28, 2026

- Added an isolated window from the companion settings menu with 16 deterministic sample
  types, shared production notification views, update/removal controls, simulated command
  results, and a last-action receipt. Samples do not use pairing, transport, or native alerts.
- Debug/release app builds and the visual review build passed. The testbed checks passed
  for bounded PNG/JPEG decoding, repeated sample deduplication, summary counts, revision
  changes, stale-command rejection, deferred confirmed dismissal, group removal, replies,
  failures, non-dismissible items, and clearing an in-flight command before recreating a sample.
- Rendered and inspected the populated testbed; scrolling/horizontal-overflow checks passed.
  Installed the release build in `/Applications/Phone Check.app` and verified its signature.
- Live UI automation could not connect to the installed app (AppleEvent timeout), so menu
  navigation and clicking the installed controls were not verified. No paired-phone or native
  system-alert tests were performed for this local preview feature.
- Follow-up: added a shared testbed model and **Show in popover** toggle. The menu-bar
  companion renders the same samples and simulated command controller, with a testbed count,
  indicator, and **Exit** control; phone transport/state remain separate. Replaced generic
  fixture icons with bounded 64-pixel PNGs from installed system apps and realistic fictional
  content. Rebuilt debug/release and review apps, reran the testbed checks, and rendered and
  visually inspected the companion preview in light/dark. Scrolling/overflow checks passed.
  Opening the actual menu-bar popover was not automated; click the menu-bar icon after enabling
  the toggle in the testbed.

## Floating macOS notification pane — October 28, 2026

- Preserved all prior work in checkpoint `354a7ac` and implemented this change on
  `codex/floating-notification-pane`.
- Replaced the SwiftUI menu-bar popover and duplicate companion window with an AppKit
  status item and a reusable borderless, nonactivating panel. It uses the right edge of
  the status item's display, a native behind-window blur with a feathered leading edge,
  and independent Liquid Glass notification cards on macOS 26 (regular-material fallback).
  There is no outer card, window border, arrow or enclosing window shadow.
- The same panel handles first-run pairing, app reopening and banner actions. Search,
  groups, action buttons, replies, confirmed phone dismissal, and the shared testbed remain
  in the existing presentation/models. Feed height follows the selected display. Escape,
  menu-bar toggling, focus changes and outside mouse events close the panel. Native menus
  are exempt from focus/local-click dismissal while tracking.
- Debug, release and visual review builds passed. All 10 core checks, six Firebase/attention
  groups, and testbed checks passed. New native-panel checks passed for secondary-display
  geometry, window/material setup, overlay scrolling/overflow, Escape, menu-bar toggle,
  native-menu tracking, focus dismissal, banner reopening and hosting-tree reuse.
  Light/dark fixture and expanded long-reply/bottom renders passed layout checks.
- Updated `/Applications/Phone Check.app`, verified its signature, and confirmed the new
  executable remained running. Preserved the previous installed bundle at
  `macos/build/Phone Check-before-floating-pane.app` (ignored build output).
- Live UI automation timed out twice. Fixture bitmap rendering does not capture the
  compositor's Liquid Glass or behind-window blur, so desktop blur appearance, actual
  mouse interaction, search/reply keyboard focus, Spaces/full-screen and multiple physical
  displays still need manual review. No paired-phone/device tests were run for this change.

## Menu-bar anchored pane — October 28, 2026

- Moved the floating pane beneath the menu-bar icon, centered on its screen-space bounds,
  with clamping at either display edge and a compact 680-point maximum height. Kept the
  independent notification cards and native blur; feathered all blur edges for the floating
  placement. Startup ignores provisional status-item bounds until AppKit has positioned it.
- Debug, review and release builds passed. Updated native-pane checks passed for icon
  centering, vertical offset, both display edges, negative screen origins, constrained
  displays, provisional startup bounds, scrolling and existing panel interactions.
- No live visual or paired-phone checks were performed for this placement adjustment.

## Native blur and appearance settings — October 28, 2026

- Reproduced the reported gray-sheet backdrop in the installed app. Added a live two-window
  material comparison over colored, detailed text. On this Mac, the legacy sidebar and
  under-window materials appeared solid; native `NSGlassEffectView` visibly blurred and
  refracted the same background. Replaced the macOS 26+ backdrop with clear native glass,
  retaining feathered edges and the regular-glass notification cards. Older macOS uses a
  standard popover material fallback, which was source-reviewed but not run on an older OS.
- Added **Settings → Appearance…** with a live 0–100% backdrop-transparency slider, saved in
  UserDefaults. The default is 35%; 100% removes the backdrop. Card opacity is independent.
  System Reduce Transparency takes priority. Reused the repository's ObservableObject state
  pattern because this command-line SDK lacks the newer SwiftUI State macro plugin.
- Debug/review/release builds and native pane checks passed. Visually verified the real pane
  against patterned background windows in light and dark appearances, and clicked a card
  expansion. Verified the settings sheet, live 35% → 75% adjustment, visible backdrop change,
  Done dismissal, and saved value in the isolated visual-review app.
- Updated and signature-verified `/Applications/Phone Check.app`. Opened its gear menu and
  **Appearance…**, confirming the saved-preference control in the actual installed panel;
  left Appearance open for the user. The paired phone reconnected and its notification
  count resumed. No phone-side dismissal/reply commands were exercised in this change.
