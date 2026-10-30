# Firebase sync

Firebase Realtime Database handles pairing, address discovery, and delivery when a local
connection is unavailable. The apps automatically prefer their encrypted LAN transport.
This implementation uses the free Spark plan and no Cloud Functions.

## Local-only pairing without sign-in

Google sign-in is optional. A signed-out Mac offers a five-minute `pc1` QR/copy code with
its private IPv4 address, port and a random secret. Android can scan or enter it without
an account, saves it in its existing encrypted pairing store, and uses only `LanTransport`.
No Firebase pairing claim, mailbox, session negotiation or address discovery is used.
Local-network permission is required on Android 17 for these pairs; notification access
is still required. Both devices must be reachable on the same LAN. A changed Mac address
requires pairing again; there is no cloud fallback for a local-only pair.

Local pairing remains local after either device signs in, including across restarts.
To enable cloud fallback, unpair and pair again after signing in on both devices.
Signing out preserves a local-only pair; signing out of a cloud pair removes that pair.

## Automatic local switching

After a cloud snapshot completes, the Mac sends `local_endpoint` with up to eight private
IPv4 addresses and its TCP port inside the encrypted Firebase mailbox. No database rules
or server changes are needed. The Mac listens on port 47831; Android probes only validated
private addresses, using the existing pairing secret and fresh mutual-authentication nonces.
The cloud route remains usable while the phone probes. A failed probe tries the next address,
then retries the list after 30 seconds. The Mac checks changed addresses every 15 seconds
while on cloud and advertises changes.

After local authentication, both sides discard the cloud route, detach control/mailbox
listeners and reconcile a fresh snapshot without replaying alerts. Mac session rotation
stops and the old mailbox is deleted; Android calls `goOffline()` and purges pending writes.
Notifications, rich assets, actions, replies, battery state and heartbeats then travel only
over the local connection. There are no periodic Firebase discovery writes while local.
Google sign-in and explicit account/pairing operations can still use the internet.

A local socket failure or 45-second idle timeout resumes Firebase with a fresh session and
snapshot. The phone receives current Mac addresses again; if none is reachable it continues
over Firebase. Cached addresses remain only in memory and are retried while cloud reconnects,
so a temporary internet outage does not prevent reconnecting to the same local address.
No queued frames or commands are copied between transports. Pending commands can become
unconfirmed during handover and are never automatically replayed.

Android 17 requires optional local-network permission; denial retains Firebase delivery.
The setup screen offers **Allow local network** without blocking cloud use. macOS uses its
existing local-network usage description and system privacy controls. Blocked LAN access
falls back to cloud. IPv6-only LANs use Firebase. Deploy both updated apps together because
older Android versions do not recognize the discovery message.
Unpairing stops local delivery; deletion initiated by the other device is observed when
Firebase reconnects, since control listeners are suspended during local operation.

## Project and client configuration

Use your own Firebase project. The current deployment uses Realtime Database in Singapore
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
ID token using Firebase Auth REST. Release builds store the Firebase refresh token in the
login Keychain; debug builds use owner-only local files (see the
[development guide](../docs/development.md)). ID tokens remain in memory and refresh before expiry. No Apple-issued signing
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
file using `firebase deploy --only database --project YOUR_PROJECT_ID --config firebase/firebase.json`
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

Automatic-switching verification (October 30, 2026): Android debug build, unit tests and lint,
and Mac debug build and core/Firebase checks pass. Deterministic route tests cover probing
without interruption, local-only delivery, cloud fallback, stale callbacks, permission denial,
address refresh, retry cancellation and revocation. No physical Android device was available
for this change; verify LAN → cloud → LAN, DHCP changes, permission denial, sleep/wake, actions
and confirmed dismissal on both devices before treating automatic switching as device-verified.
