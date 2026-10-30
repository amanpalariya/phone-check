# Phone Check

## Status
Implementation authorized by the user on October 27, 2026. Both apps live in this repository. Keep UI copy minimal.

## Product and current scope
A lightweight Android app and macOS companion. One phone paired to one Mac. The user expanded the original text-only milestone to rich notification mirroring, original notification actions, text replies, opening on phone, and an Android notification testbed.

- Android forwards app identity/icon, supported rich content, stable keys, updates, removals, and opaque action capabilities. Include an in-app testbed for real OS notifications and action receipts.
- Mac shows mirrored notifications and an explicit **Dismiss on phone** action.
- Dismissal sends a command to Android; confirm removal before reporting success. Phone-side removals also clear the Mac copy.
- Include only essential pairing, permission explanations, connection status, and empty/error states.
- Reconcile active notifications after reconnect; deduplicate updates. Expire stale commands and avoid replaying old alerts.
- Support big text, inbox, messaging, bounded picture previews, progress, groups, media/call notification controls, ordinary PendingIntent actions and one text/choice RemoteInput. Custom RemoteViews use a text fallback. Unsupported attachment/multiple-input actions stay disabled. Calls here mean notification controls, not audio transport.
- Show phone battery level, charging state, and active Battery Saver in the Mac panel header, replacing the connection dot and header notification count; the menu-bar notification count remains. Hide the battery indicator while unpaired. Keep device status independent of notification state and transport.
- Exclude status dashboards, clipboard, file transfer, notification history, account-management screens beyond Google sign-in, and multi-device support.
- Keep code readable and modular: separate capture/assets, command validation/execution, transport, presentation, and deterministic fixtures without adding speculative frameworks.

## UI direction
Reference: [Blip](https://blip.net/) and its installed macOS app, visually inspected October 27, 2026. Borrow its compact hierarchy and spacing, not its branding or a shared cross-platform theme.

- Platform design systems take priority: native macOS Liquid Glass on macOS 26+ with a standard-material fallback, and Android Material 3 with system dynamic color on Android 12+. On Mac use the system accent and neutral primary notification text/icons; Android keeps a purple fallback accent. Respect system appearance.
- Clear typography, generous whitespace, restrained rounded controls, minimal borders and shadows.
- Mac presentation: clicking the menu-bar icon opens a borderless pane beneath the menu-bar icon, centered on the icon and constrained to its display, with a soft, feathered desktop blur and separate notification surfaces. No enclosing popover or outer card. Keep the title and search in one notification-style card close beneath the menu bar. Reserve Liquid Glass for cards and controls. Use the isolated blur-only compositor renderer on supported OS generations with NSVisualEffectView fallback; see CompositorBackdrop.swift for undocumented API boundaries. Never read back background pixels. The backdrop follows visible content with broad soft edges, a dark wash in both light and dark mode, and no empty tail. Blur and backdrop strength use fixed subtle defaults with no customization or saved appearance overrides; the backdrop stays dark while cards follow system appearance. Fade the list’s bottom only while more notifications remain below, and reveal the last item fully at the end. Escape, outside click, or clicking the icon again closes it.
- Mac notifications: collapsed rows have a large app icon on the left, message preview, and centered expand control on the far right; app names appear only when expanded. Expanded groups use a plain text heading above separate notification cards, never cards nested inside a group card. Dismissal is a neutral hover cross with a matching circular background. Ordinary notification actions use equal-width text buttons in a shared footer with thin vertical dividers (One UI Gmail/WhatsApp reference), not individual pills or icons. Suggested replies are separate chips, media controls are circular, and incoming-call actions are semantic-color pills.
- One obvious primary action per state; short, friendly copy. No decorative dashboards or dense card grids.
- Respect platform conventions, system appearance, accessible contrast, text scaling, and keyboard/screen-reader access.
- Android: Kotlin, Jetpack Compose, Material 3. macOS: Swift, SwiftUI; prefer a compact menu-bar companion with minimal setup.

## Platform and architecture guidance
Checked official documentation October 27, 2026; recheck stable SDK/tool versions when implementation starts.

- Android: use `NotificationListenerService`, with user-enabled notification access. Wait for `onListenerConnected()` before reading active notifications or calling `cancelNotification(key)`. Respect non-dismissible notifications and system-redacted content; do not promise access to every notification.
- macOS: use `UserNotifications` for system alerts; request authorization in context. Register a notification category and handle its explicit dismissal action. Evaluate `.customDismissAction` for user dismissals; never treat a banner timing out as phone dismissal.
- Android group summaries are containers, not extra message rows or Mac alerts when children are present. Keep their original capabilities in a secondary-click context menu; no three-dot menu. The menu-bar count includes actual notifications, excluding represented summaries. The panel header shows phone battery instead of a dot or duplicate notification count; connection state remains available in its accessible label and existing empty/settings states.
- On October 29, 2026 the user authorized creating the Firebase project and selecting Firebase as the only transport, while retaining LAN code for a future settings option. The project is `phone-check-fcd4f`, on free Spark with Google sign-in and Realtime Database in Singapore. Mac uses browser OAuth with PKCE and Firebase REST; Android uses Credential Manager and the Firebase SDK. Do not enable billing. Pairing/session authorization uses owner-scoped database rules and device-secret HMAC proofs; Cloud Functions are not required. Client configuration files are local and gitignored. See `firebase/README.md` for current integration, deployment and verification status. Keep notification logic independent of transport.
- On October 30, 2026 the user authorized automatic Firebase → authenticated LAN switching and Firebase fallback. Discover private Mac addresses inside encrypted Firebase messages; stop cloud sync while local, resume fresh sessions on failure, and retain cloud delivery when local permission is denied. This supersedes the Firebase-only selection above. See `firebase/README.md` for handover details.
- Google sign-in is optional. Signed-out users can pair directly over LAN with `pc1` codes and sync without Firebase. Persist local-only pairing across restarts and later sign-in; require explicit re-pairing to enable cloud fallback. Local-network permission is required for local-only pairs.
- If targeting Android 17/API 37+, local networking needs `ACCESS_LOCAL_NETWORK` runtime permission or an applicable system-mediated picker. Check macOS local-network privacy requirements too.
- Pair explicitly before forwarding content; never log notification bodies or credentials. Keep only the active state needed for syncing.
- Validate on a physical Android phone and Mac: post, update, dismiss from either device, reconnect, deny/revoke access, and non-dismissible notifications. Report actual build/device verification separately from source review.

## Official references
- [Android notification listener](https://developer.android.com/reference/android/service/notification/NotificationListenerService)
- [Android local network permission](https://developer.android.com/privacy-and-security/local-network-permission)
- [Compose BOM and compiler guidance](https://developer.android.com/develop/ui/compose/bom)
- [Apple notification authorization](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [Apple notification actions](https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types)
- [Apple custom dismissal callbacks](https://developer.apple.com/documentation/usernotifications/unnotificationcategoryoptions/customdismissaction)
