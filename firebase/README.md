# Firebase sync

Firebase Realtime Database is now the only selected app transport. The LAN implementations
remain in source for a future settings option; there is no LAN listener, permission request,
or automatic fallback in normal Firebase operation. Both devices need internet access, not
the same network. This implementation uses the free Spark plan and no Cloud Functions.

## Project and client configuration

The Phone Check project is `phone-check-fcd4f`. Its Realtime Database is in Singapore
(`asia-southeast1`); Google is the enabled Firebase Authentication provider. Analytics and
Gemini were not enabled. The support address is the project owner's approved Google address.

Download the project configuration from Firebase project settings:

- Android: `android/app/google-services.json`. Google Services generates the app resources;
  Firebase initializes from them. Google sign-in uses Credential Manager and Firebase Auth.
- macOS: `macos/GoogleService-Info.plist`. The build script bundles it. The REST clients read
  its project ID, API key and database URL.
- Mac browser login: `macos/GoogleOAuthClient.json`, the downloaded JSON for a **Desktop app**
  OAuth client in the same Google project. The build script bundles it as well. Google treats
  installed apps as public clients; the supplied client secret is not an Admin/service-account key.

All three files are gitignored. They contain client project identifiers, not Admin credentials.
They must contain the database URL and Google OAuth client IDs. Register the Android signing
certificate SHA-1 before downloading the Android file. The current local debug certificate
is registered; production release signing needs its own fingerprint. CI must supply the three
files before building. No service-account keys belong in either app or this repository.

The Mac uses system-browser Google OAuth authorization codes with PKCE, random state and
nonce, and a temporary callback listener restricted to `127.0.0.1`. It exchanges the Google
ID token using Firebase Auth REST and stores only the Firebase refresh token in the classic
login Keychain. ID tokens remain in memory and refresh before expiry. No Apple-issued signing
certificate or native Google/Firebase Apple SDK is required. macOS can request Keychain approval
after ad hoc rebuilds. Android uses Firebase Auth, BoM 34.19.0 and Google ID 1.1.1, compatible
with the current built-in Kotlin compiler; newer versions checked require newer Kotlin metadata.

## Authentication and explicit pairing

Sign in with the same Google account on both devices. The Android SDK and Mac REST binding manage token persistence
and refresh. A Google account establishes database ownership, not the right to decrypt content.
There is one `accounts/{FirebaseAuthUID}` record with one explicit phone–Mac pairing.

The Mac creates a five-minute invite and a random 256-bit secret. The QR code is
`pc2|projectID|ownerUID|pairID|base64url(secret)`. Android checks project/account identity and
atomically claims the unexpired invite with a fresh phone UUID and an HMAC proof. The Mac
verifies that proof before accepting the phone. The secret is never uploaded. It stays in
Mac Keychain for release builds (the existing owner-only development file for debug), and
in Android preferences encrypted with an Android Keystore key. Existing LAN codes must be
replaced by a new cloud pairing. Signing out removes the cloud pair before clearing local
pairing and authentication. Unpairing from either device removes the cloud record.

Rules isolate Google accounts. Both devices share the same Firebase UID, so rules intentionally
do not distinguish phone and Mac writes. Device authenticity instead uses the shared secret,
direction-specific encryption keys and authenticated session negotiation. These rules are not
the old separate-device-UID provisioning template.

## Session negotiation and data

```
accounts/{uid}/
  control/
    pair:    { id, expiresAt, phone?, proof? }
    request: { id, peer, proof }
    offer:   { id, request, expiresAt, proof }
  mailboxes/{fresh-session-uuid}/
    phoneToMac:    encrypted packet string
    phoneToMacAck: decimal sequence string
    macToPhone:    encrypted packet string
    macToPhoneAck: decimal sequence string
```

Each phone transport start/reconnect sends a fresh request UUID with a pairing-secret HMAC.
The Mac verifies it and publishes a fresh session UUID, matching request UUID, expiry and
HMAC binding all those fields to the paired phone. Android verifies the offer and refuses a
previously used session ID. Sessions last at most fourteen minutes and rotate after twelve.
Each reconnect constructs new ciphers and silently reconciles active notifications. Snapshot,
notification actions, confirmed dismissal and battery status use the existing shared protocol.

HMAC labels are `cloud-pair` (phone UUID), `cloud-request` (`request|phone`) and `cloud-offer`
(`session|request|phone|expiry`). All use the existing `phonecheck-v1/{label}/` derivation.
Notification encryption still uses AES-256-GCM with independent `firebase-phoneToMac` and
`firebase-macToPhone` direction keys derived from the secret and fresh session UUID. The
protocol has no forward secrecy and has not received an independent security audit.

Notification bodies, icons, pictures, reply text and commands are encrypted before Firebase
receives them. Account/pair/session identifiers, HMAC proofs, expiry, ACKs, timing and sizes
are visible metadata. Firebase SDK/REST traffic also uses TLS. Do not log bodies or credentials.

Only one frame per direction is outstanding; matching transport ACKs prevent RTDB from
coalescing away snapshot chunks or actions. ACKs mean delivery, never phone-action success.
Frames expire after 30 seconds or session expiry. Existing eight-second command lifetimes,
revision validation and explicit phone results remain authoritative. Old alerts are never
replayed after reconnect. Device status is independent of notification reconciliation.

## Cleanup and offline behavior

Android disables SDK disk persistence; Mac uses ephemeral REST sessions and no disk cache.
Pending Android SDK writes can exist in memory while offline,
but remain bound to their original session path; rules reject expired or replaced sessions
and receivers reject expired encrypted frames. There is no durable command outbox or history.

Android registers server-side `onDisconnect` removal of each mailbox, and explicitly removes
it when its transport disconnects or times out. Mac removes its mailbox when stopping. Rotation
atomically deletes every previous mailbox before publishing the new offer. Unpair/sign-out
deletes the account record. Rules deny reads/writes to expired or noncurrent sessions, while still allowing
owner cleanup. Expiry is an access control, not scheduled TTL deletion: Spark has no scheduled
cleanup job here. `onDisconnect` handles lost device connections; later reconnect also removes
any leftover mailbox. Pairing/control metadata persists until unpair/sign-out or replacement.

This is a real-time stream while the Mac app and Android notification listener can run.
FCM/APNs wake delivery and guarantees for suspended/terminated apps are not implemented.
Android Doze, revoked access and OS background limits can interrupt or delay syncing.

## Verification and deployment

`database.rules.json` denies all unspecified access. Run its local emulator tests with:

```sh
npm ci --prefix firebase
# Requires Java 21+ on PATH or JAVA_HOME.
npm test --prefix firebase
```

The tests cover unauthenticated/cross-account denial, bounded invites, single peer binding,
unknown/oversized data, expired sessions, atomic rotation and cleanup. Deploy the exact tested
file using `firebase deploy --only database --project phone-check-fcd4f --config firebase/firebase.json`
from the repository root after authenticating the Firebase CLI, or publish the same JSON in
the console. The tested rules were published to the live database on October 29, 2026 with user approval.

Source/build checks do not establish real-device delivery. Verify Google login, explicit
pairing across different networks, post/update/action/reply/confirmed dismissal, reconnect,
sleep, token refresh, permission revocation and unpairing on a physical phone and Mac.

References checked October 29, 2026:
[Android Google authentication](https://firebase.google.com/docs/auth/android/google-signin),
[Google desktop OAuth](https://developers.google.com/identity/protocols/oauth2/native-app),
[Firebase Auth REST](https://firebase.google.com/docs/reference/rest/auth),
[database rules](https://firebase.google.com/docs/database/security/core-syntax),
[disconnect cleanup](https://firebase.google.com/docs/database/ios/offline-capabilities#how_ondisconnect_works).

Current verification: both debug apps build; 19 Android unit tests and Android lint pass;
11 Mac core checks, 9 Firebase/device-state check groups, and the Mac settings/testbed/pane checks
pass; 5 database emulator tests pass. A live unauthenticated database read returned 401.
Both apps were installed on the user's physical Android phone and Mac, and the user reported
that the integration works on October 29, 2026. This is user-reported device verification;
the full post/update/action/reply/dismissal/reconnect/revocation matrix above was not separately
exercised by the agent during this session.

Connection follow-up: Android invalidates pending retries when it accepts a session and
ignores errors from superseded requests. Mac mailbox shutdown cancels IO without invalidating
the URLSession while an authentication-token provider is suspended. Regression checks cover
both races. Updated apps were installed without clearing pairing; the agent observed live
notifications, battery status and a sustained Connected state on the physical Mac/phone.
