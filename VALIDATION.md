# Validation — October 27, 2026

## Device installation — October 30, 2026

- Installed the latest development Mac build at `/Applications/Phone Check.app`, verified its code signature and executable against the build output, and relaunched it.
- Updated the connected Samsung Galaxy S23 (SM-S911B) using `adb install -r` without clearing app data; installation succeeded and MainActivity launched. This confirms installation/launch only; automatic handover and unsigned local sync have not yet been exercised between these physical devices.

## Signed-out local sync — October 30, 2026

- Mac signed-out startup now starts its LAN listener and offers local QR/copy pairing. Android accepts local codes without account/project checks, persists local pairing, and selects the LAN transport without creating a Firebase mailbox. Sign-in is optional in setup; local-network permission blocks only local-only pairs.
- Local pairs survive later sign-in and sign-out. Cloud pairing keeps the automatic local/Firebase behavior; enabling cloud fallback for a local-only pair requires explicit unpair/re-pair.
- Both development apps build. Android's 31 unit tests and debug lint pass; the adapted unsigned pairing/permission instrumentation APK compiles. No phone or usable emulator was available, so Android UI/device execution remains unverified.
- `tests/local/check-unsigned-local.sh` passed against the production Mac companion with no cloud config/account and an encrypted simulated phone over real loopback TCP: default signed-out startup, five-minute local QR, rejected unknown secret, snapshot/battery sync, persisted peer identity, dismiss command and simulated confirmation, fresh-nonce reconnect, and unpair cleanup. This verifies transport/model behavior on Mac, not Android OS notification dismissal or hardware Wi-Fi/privacy behavior.

## Automatic local switching — October 30, 2026

- Added encrypted Firebase address discovery, authenticated LAN probing, local-only notification/action delivery with Firebase streams and rotation stopped, and fresh-session Firebase fallback. No Firebase rules or server deployment changes. Android local-network permission remains optional.
- Android development APK, 29 unit tests (including 10 deterministic automatic-route tests), and lint pass. Mac development build/packaging, 11 core checks and 10 Firebase/device-state groups pass, including encrypted address delivery and detached observer cleanup.
- Route fixtures verify continued cloud delivery while probing, local-only writes after authentication, fallback without command replay, late-callback suppression, retries across addresses, changed-address probe cancellation, cached-address recovery while cloud reconnects, denied permission, stop and revocation.
- No physical Android phone was connected (only an offline emulator). Actual LAN/cloud handover, bandwidth reduction, sleep/wake, DHCP changes, actions/replies/confirmed dismissal and permission revocation were not verified on devices. Built artifacts are available; apps were not installed or relaunched for this change.

## Pairing in the Mac panel — October 29, 2026

- Moved pairing into the menu-bar panel: device welcome, QR code, actual expiry countdown, optional Mac address selector, cancellation, and copy confirmation. First launch/reopening opens the panel; Settings routes pairing there and retains phone management.
- Development Mac build and ad hoc packaging passed. Existing pane geometry/interaction checks passed. QR decoding checks passed for three addresses in light and dark.
- Inspected the native welcome and QR surfaces through computer use in light/dark, verified the countdown and Copy code → Copied feedback. Fixed native dark-mode QR contrast by preserving original image colors and using a light QR surface. Cached view rendering cannot reproduce native glass; final appearance was checked in the live fixture.
- Pairing polish: replaced blue text actions with equal-width native filled buttons (red Cancel, neutral Copy code), with contrasting labels in each appearance, and increased the expiry countdown to medium-weight callout text.
- Updated and relaunched `/Applications/Phone Check.app`. Physical-phone pairing, cancellation/expiry, and the transition after authenticated connection were reviewed in source but were not rerun on a physical phone.

## Phone battery header — October 29, 2026

- Added OS battery/Battery Saver capture, shared encrypted `device_status` messages, and a Mac header battery indicator with percentage, green charging bolt, and amber Battery Saver leaf. Both indicators can appear together. Removed the header notification count; menu-bar counting is unchanged. Unknown/disconnected readings use an em dash and an accessible status label.
- Android debug/release APK builds passed. All 13 debug unit tests passed; debug lint: 0 errors, 9 warnings, 2 hints. Battery tests cover scale normalization, invalid/missing readings, absent batteries, integer overflow, and JSON shape.
- Mac debug/release builds and ad hoc packaging passed. 11 core checks and 7 Firebase/device-state check groups passed, including Android-shaped battery JSON and ordered encrypted battery changes over the Firebase mailbox fixture. No live Firebase project was used.
- API 37 emulator battery integration passed against the production Mac companion model: initial 73%, Battery Saver enabled/disabled without a level change, Battery Saver retained across reconnect, charging change, live 19%, reconnect snapshot, clearing on access revocation, and 100% after restoration. The existing notification post/update/confirmed-dismiss/reconnect/revoke flow also passed. Emulator battery overrides and Battery Saver were reset in cleanup.
- Rendered the native header in light/dark fixtures and checked percentage/icon spacing, simultaneous saver/charging symbols, and centered title. The app-owned renderer does not reproduce the desktop compositor backdrop; live computer-use inspection timed out. Physical-phone battery and vendor power behavior remain unverified (only an emulator was connected).
- Installed the updated development Mac app in `/Applications/Phone Check.app`, verified its signature, and relaunched it. Android APKs are built; no physical phone was installed. Deploy both updated apps together: older Mac builds reject the new message type. Production Firebase provisioning remains pending a project.

## Development and release separation — October 29, 2026

- Built and ad hoc signed both Mac configurations; left `macos/build/Phone Check.app` as development and copied it to `/Applications/Phone Check.app`; verified its signature and launched it. Verified the development executable has no Keychain item API references; release retains Keychain item APIs and contains no testbed/fixture symbols.
- `tests/ui/check-credentials.sh` passed: separate-process persistence, replacement, 0700 directory/0600 file modes, corrupt-data rejection, idempotent removal, and write-error propagation. Uses a unique test bundle identity and cleans up its pairing file.
- Mac core checks passed (10 core checks and 6 Firebase/attention groups). Existing Mac testbed and pane checks passed, including simulated actions/replies/removals and pane geometry/interaction.
- Android debug/release APK builds, debug unit tests, and lint for both variants passed. Inspected both APK DEX files and merged manifests: testbed classes/components occur only in debug. Bare Gradle dry-run selects `:app:assembleDebug`.
- Rebuilt the Mac emulator host with development credential storage. Physical-phone pairing, repeated installs/relaunches, and device notification flows were not rerun for this change; earlier device results below are historical.

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

## Opposite-tone backdrop — October 28, 2026

- Backdrop appearance now follows the opposite of the surrounding system appearance:
  dark in light mode, light in dark mode. Clear glass receives a matching restrained tint;
  cards and controls continue to inherit the system appearance. Effective-appearance
  changes update the backdrop immediately without changing the saved transparency value.
- Debug/review/release builds and native-pane checks passed, including live light/dark
  appearance switching and verification that notification content retains its appearance.
  Inspected the actual patterned-background preview in both modes. Updated the installed app.

## Adaptive native backdrop default — October 28, 2026

- Checked Apple's AppKit glass style API, SDK headers and material guidance. Public glass
  styles are regular and clear; there is no public Notification Center backdrop preset.
  NSBackgroundExtensionView extends in-window content around safe areas and is not a
  desktop backdrop replacement. Retained the menu-bar placement and soft edge geometry.
- System is now the default under Settings → Appearance. It uses native regular glass,
  inherited appearance, nil tint and full material opacity so AppKit can adapt it. Custom
  retains the previous clear-glass inversion and saved transparency slider. Switching modes
  does not reset the saved custom transparency. Older macOS retains its standard-material
  fallback; no private material/style values or compositor APIs were added.
- Debug/review/release builds and native pane checks passed, including System/Custom mode
  switching in light/dark, native appearance inheritance, nil tint/full opacity in System,
  and opposite appearance in Custom. Visually inspected System mode over a detailed
  two-window background. Updated and signature-verified the installed app.
- UI automation could inspect a desktop calendar widget owned by Notification Center but
  could not open the full system notification pane: the Fn modifier is unsupported by the
  tool and system menu-bar app access timed out. No exact visual-match claim is made.
  Attempts to inspect the new settings selector encountered stale/user-changed UI state;
  the mode-switch behavior above was exercised by the native harness, not a live click test.

## Separate backdrop material from card glass — October 28, 2026

- Corrected the surrounding pane to use NSVisualEffectView with underWindowBackground,
  behindWindow blending and active state on all supported macOS versions. Removed the
  surrounding NSGlassEffectView and glass-specific tint/style logic. Notification cards
  retain their independent Liquid Glass surfaces. System/Custom appearance preferences,
  opposite-tone custom mode, saved transparency and accessibility behavior remain available.
- Debug, review and release builds and native pane checks passed. Checks now require the
  standard backdrop material and behind-window blending, plus System/Custom appearance
  behavior. Updated the installed app and verified its signature.
- Separated the review windows into independent groups for behind-window sampling. The
  tool's window screenshot did not include the separate patterned background and showed
  a uniform material, so it did not establish live desktop blur quality. This is an API-role
  correction, not a verified match to Notification Center's compositor effect.

## Localized Notification Center-style wash and overflow cue — October 28, 2026

- The user opened the real Notification Center for direct inspection. Observed its soft,
  localized dark wash and broad fade around the visible notification content, rather than
  a tall material rectangle below a short list. This informed the geometry and dimming;
  it does not establish Apple's private compositor implementation or exact blur parameters.
- Reworked the backdrop into the existing behind-window material plus a feathered black
  wash. It remains dark in both light and dark appearance, per the user's correction;
  cards retain their system appearance. Automatic uses the default strength; Custom keeps
  the saved strength slider. Reduce Transparency continues to take priority. No private API,
  screen capture pipeline, background-glass sheet, or new dependency was introduced.
- Measured the visible companion content, including the bounded feed viewport, and sized the
  backdrop to that content with a fixed soft falloff. Search, updates, expansion and empty
  states update its extent. Removed the blank panel-height tail for short/filtered lists.
- Added a 32-point bottom fade to the scroll viewport only while notifications remain below.
  It updates during native scrolling and layout, and disappears at the end so the final
  notification is fully visible. Kept overlay scrollers, viewport anchoring and keyboard/
  accessibility access to the native list. The clip layer also clips overflowing card content.
- Debug/review/release builds and native pane checks passed. Checks cover localized backdrop
  growth/shrinkage, dark backdrop in both appearances, system-style notification content,
  overflow cue presence and removal at the end, and existing window interactions. Expanded
  long-text/bottom fixture rendering passed scrolling/horizontal-overflow checks.
- Live UI checks passed for dark-mode overflow fading, scrolling to the final unfaded item,
  filtering down to one notification and shrinking the wash, and the dark backdrop with
  light-mode cards. Updated and signature-verified the installed app. Phone-side commands
  were not exercised for this presentation change.

## Header card, closer anchoring, and subtle blur-only renderer — October 28, 2026

- Grouped the Phone Check header, status/count and search field into one surface shared
  with notification cards. Testbed controls stay inside that surface. The feed accepts an
  external query binding so search remains functional without a second search field.
- Reduced the menu-bar gap to 2 points and pane content inset to 6 points (previously 6
  plus 32). Updated backdrop geometry and placement checks to preserve the localized wash.
- Reproduced the user's observation that dimming a stock material was not providing the
  desired visible blur. Added a comparison against a blur-only compositor layer over sharp,
  colored text. The user confirmed the right-hand renderer blurred that background, judged
  radius 22 too harsh, then confirmed radius 4 was recognizable but requested still less.
  The app defaults to 2 and saves a separate Blur amount slider (0–12), independent of the
  existing transparency/strength preference. Edges retain the content-sized soft mask.
- Isolated undocumented CABackdropLayer/CAFilter/window-hosting hooks in
  CompositorBackdrop.swift, limited to macOS 26–27 with runtime capability checks. Kept
  protected-content substitution enabled and no pixel readback/screen-recording pipeline.
  Older/unsupported systems and Reduce Transparency retain the standard-material fallback.
  The slider is shown only where the blur-only renderer is available. This is not an App
  Store-safe API path, and future OS compatibility requires revalidation before extending
  the supported version range. Spaces/full-screen transitions remain unverified.
- Debug/review/release builds and native panel checks passed during implementation. Checks
  cover renderer selection, shared localized mask bounds, closer icon anchoring, dark
  background, scrolling/fade and existing panel interactions. Live preview verified the
  combined header/search card and filtering from the relocated search field. Standalone
  companion render passed horizontal-overflow and native scrolling layout checks.
- Installed build updated after final verification. Window screenshots showed a solid
  backdrop while the user confirmed live blur; actual blur validation came from
  the user's on-screen comparison. The final radius-2 integrated pane remains subject to
  the user's visual preference; the setting allows immediate adjustment. No paired-phone
  actions were issued for this presentation change.


## Menu-bar pointer and contained setup states — October 28, 2026

- Added a small upward pointer as part of the top card's material outline, with its
  horizontal position derived from the menu-bar button and constrained away from corners.
- Moved pairing, disconnected/empty states, alert permission controls, and errors inside
  the header card. Mirrored notifications retain their separate surfaces below it.
- Debug, release, and isolated native review builds passed. Existing pane checks passed,
  including geometry, blur bounds, scrolling, Escape, menu toggle, focus and reopening.
  The light/dark setup fixture passed horizontal-overflow/layout checks; its cached image
  confirmed containment and pointer geometry but showed glass-rendering artifacts, so it
  does not verify live material appearance. No paired-phone actions were exercised.

- Follow-up: softened the pointer to match the supplied Blip reference, using a 40-point
  base and a rounded 12-point rise. Cubic curves meet the card and crest with horizontal
  tangents. Release build and diff whitespace check passed; live visual review pending.
- Raised the pane content by 4 points (top inset 6 → 2) at the user's request.
  Release/review builds and native pane checks passed with updated backdrop bounds.

## QR pairing — October 29, 2026

- Committed the preceding Android settings changes as `e61e4b0` before starting QR pairing.
- Mac now displays a locally generated QR for the current pairing code. Android offers
  Google Play services QR scanning, with cancellation, unavailable-scanner feedback, and
  manual entry retained. Both paths use the existing private-address/key validation and
  Keystore storage; Mac cancellation and the five-minute expiry still apply.
- Android debug APK build, unit tests, and lint passed. Updated the scanner's transitive
  Fragment dependency to 1.9.1 to preserve Activity Result compatibility.
- Mac release app build and existing core checks passed. Vision decoded the actual SwiftUI
  QR surface for three private addresses in both light and dark appearances, preserving
  the exact pairing payload. Reproduce with the QR check command in README.md.
- Physical camera scanning, first-use scanner download, unavailable Play services,
  rotation/cancellation, expired-code rejection, and end-to-end pairing remain to be
  checked on devices. No installed apps or existing device pairing were changed.

### Device follow-up and app identity — October 29, 2026

- Installed and launched the QR builds on the Mac and connected Samsung phone without
  clearing app data. The user reports that QR pairing worked flawlessly.
- Added launcher-intent package visibility so Android can resolve source app labels and
  icons rather than falling back to package names. Failed icon lookups are no longer
  cached for the rest of a connection.
- Android APK build, unit tests, lint, and instrumentation APK build passed. Added a device
  regression check using an independent shell list of launcher apps, checking production
  capture labels and bounded, decodable icons without reading real notifications.
- Installed the identity fix on the reconnected Samsung SM-S911B without clearing app data.
  `AppIdentityTest` passed on the physical phone: production capture resolved the labels
  and decodable icons for its launcher apps. Relaunched Phone Check after the check.
  Mac appearance of each real notification remains subject to visual confirmation.
  Apps without launcher entries and restricted profiles may still have metadata restricted
  by Android.

## Native settings and Firebase reconnect — October 29, 2026

- Mac settings now uses a native preferences toolbar for General, Account, Devices and
  development-only Advanced. Android uses Material 3 settings pages with the same essential
  functions. Google identity is cached with the existing login record; older records decode.
- Both debug apps built and were installed without clearing data. Android account/sign-out
  confirmation was visually checked (cancelled); Mac account and connected-device settings
  were visually checked. Mac settings content was reviewed in light and dark appearances.
- Fixed an Android retry firing after a valid session offer, and a Mac crash when a suspended
  token request resumed after URLSession invalidation. Added three retry regressions and a
  mailbox close-during-token-refresh regression for both reads and writes.
- 19 Android unit tests and lint passed; 11 Mac core checks, 9 Firebase/device-state groups,
  and settings, testbed and pane checks passed. The live Mac received phone notifications and
  battery status and stayed Connected during follow-up; Android's current process logged no
  permission-denied errors or fatal exceptions. Long-duration/sleep/token-expiry testing and
  the complete notification action matrix remain separate device checks.


## Background operation and route indicator — October 30, 2026

- Android keeps sync in the system-bound notification listener, independent of activity
  visibility and display state. Added debounced recovery on network changes and after
  Doze, with callback cleanup on service destruction. No new settings or permission prompts.
- Added a deadline for unanswered cloud session requests so a sleeping/offline Mac cannot
  leave Android waiting indefinitely. Regression checks cover timeout, acceptance and stop.
- Mac holds an App Nap activity only while paired/pairing and awake; it allows system sleep.
  Sleep closes the listener and active connections, stops cloud sync, clears transient state,
  and releases the activity. Wake starts fresh services. Listener failures retry automatically.
- The header shows the synchronized session's actual local/cloud route next to Settings;
  disconnect resets it. Battery presentation and the menu-bar count remain independent.
- Android debug app, instrumentation APK, unit tests and lint passed. Mac debug build,
  11 core checks, 10 Firebase/device-state groups and native pane checks passed.
  The isolated `--lifecycle-only` check passed with a simulated transport, covering sleep,
  rejected connections while asleep, wake, route reset and activity release on unpair.
- The socket-based local integration check could not run: even a standalone Network.framework
  listener fails here with POSIX EINVAL (22). Port 47833 isolates checks from the installed app.
  Added screen-off post/update/dismiss instrumentation coverage; it compiles but was not run.
  No Android device is attached. Physical screen-off/deep-idle behavior, real Mac sleep/wake,
  cloud/local handover and live icon appearance still require device verification.
