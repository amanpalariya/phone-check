# Firebase sync

Firebase Realtime Database is the intended production transport. LAN remains the configured
transport while there is no Firebase project. Both apps now contain an HTTPS/SSE RTDB client
and an encrypted mailbox adapter. They are compiled, but are not reachable from setup UI yet.
No database URL, credentials, service account or project is checked in. No cloud requests occur
in the current app configuration.

## Boundaries

- Android `NotificationTransport`: ordered start/send/batch/disconnect/stop lifecycle.
  `NotificationBridge.useTransport` is the composition point for a provisioned session factory.
  It bypasses LAN permission checks for cloud sessions. The bridge continues to own capture,
  active reconciliation and command execution; a transport never invokes Android actions.
- Mac `NotificationConnection`: an authenticated ordered session, implemented by both
  `FramedConnection` and `FirebaseConnection`. `Companion.connect(using:)` connects the latter
  to the same snapshot validation, active state, actions, confirmed dismissal and alerts.
- `FirebaseMailbox`: observe a string leaf and write a string leaf. `FirebaseRESTMailbox`
  implements it using authenticated HTTPS PUT and real-time Server-Sent Events. It can also
  be backed by a Firebase SDK without changing notification code. Tests use in-memory mailboxes.
- `PhoneAttention` and `AlertPolicy`: phone screen/unlock signals and Mac presentation decisions,
  independent of LAN versus cloud. A screen that is interactive and unlocked counts as in use.
  This is a proxy, not foreground-app tracking or proof of touch input. Notifications keep
  syncing while banners are suppressed. Screen/unlock changes and each live upsert refresh the
  signal. Old activity samples cannot overwrite a newer sample. Suppressed alerts are not replayed
  when the phone locks. Reconnect snapshots are always silent.

## Database shape

The trusted provisioning service must create this record only after explicit mutual pairing:

```
pairs/{opaquePairID}/sessions/{freshLowercaseUUID}/
  phoneUID       Firebase Auth UID of this phone
  macUID         Firebase Auth UID of this Mac (must differ from phoneUID)
  expiresAt      server Unix milliseconds, at most 15 minutes after issuance
  phoneToMac     encrypted packet JSON stored as a string, initially absent
  phoneToMacAck  decimal sequence stored as a string, initially absent
  macToPhone     encrypted packet JSON stored as a string, initially absent
  macToPhoneAck  decimal sequence stored as a string, initially absent
```

The client token providers supply **Firebase Auth ID tokens** for their own device identity,
refreshing them before expiry. Device identities need no account UI. A Firebase API key is not
an ID token. Clients must never receive Admin credentials or permission to create session
metadata, choose peer UIDs, extend a session, or grant themselves pairing access.

`database.rules.json` is a deny-by-default template: each UID can write its own direction and
acknowledge only its peer's direction. A device cannot read an entire session or a different pair.
Session metadata is writable only by the trusted backend. These rules have not been deployed
or tested against a Firebase emulator/project. Test role isolation, unauthenticated access,
expired sessions, oversized leaves and metadata writes before deployment. Do not use test-mode
public database rules.

## Delivery and encryption

Each direction has **one outstanding frame**. A sender waits for the matching transport ACK
before replacing its mailbox. This avoids losing snapshot chunks or commands when RTDB
coalesces value events; it also bounds stored content to two encrypted frames and two ACKs
per live session. Pending frames remain in memory, limited to 256 frames / 32 MiB. No disk
cache, durable command outbox, notification history or `push()` log is used.

Packet string: `{"sequence":1,"payload":"base64(ciphertextAndTag)"}`.
The encrypted UTF-8 JSON contains `session`, `sequence`, `expiresAt`, `message`.
Direction key: existing HMAC derivation with label `firebase-phoneToMac` or
`firebase-macToPhone` and UTF-8 session UUID as material. AES-GCM and its implicit counter
match the existing platform ciphers. Frame sequence starts at 1; cipher counter starts at 0.
The session ID must be fresh and jointly authorized; reusing it with the same pairing secret
would reuse cipher nonces. Session IDs and ACKs are metadata; notification bodies, rich assets,
reply text and commands are encrypted before upload. This PSK design has the same lack of
forward secrecy as LAN and has not received an independent security audit.

Frames expire after 30 seconds or at session expiry, whichever comes first. Duplicate accepted
frames are ACKed without repeated delivery. Gaps, bad ciphertext, old sessions, invalid data,
permission revocation, stream closure and HTTP errors close the session. No HTTP write is
retried by the transport. A mailbox ACK confirms delivery, never phone action success. Existing
8-second command validation and explicit phone results still apply.

The Mac's normal 15-second ping/pong also runs over Firebase. Both ends close after 45 seconds
without valid inbound frames/ACKs, or at session expiry. No reconnect reuses the same session.
The composition layer must acquire a new jointly authorized session, replace both transports,
and let the phone send a new snapshot. Devices need reasonably synchronized clocks. Switching
between cloud and LAN must also replace the session and clear pending commands.

## Wiring when the project exists

1. Create the project, enable RTDB and device Firebase Auth, and test/deploy the rules.
2. Implement authenticated mutual pairing/session issuance and revocation on a trusted backend.
   Bind exactly one phone UID and one Mac UID to a pair; never put the pairing secret in RTDB.
   Both devices must verify that a session came from their authorized peer. Do not initialize
   `FirebaseSession` from arbitrary database content. Reuse the explicitly paired secret, or
   securely establish a new one during cloud pairing.
3. Supply database URL, pair ID, fresh session ID, secret and expiry at the composition points:
   - Android: construct `FirebaseRESTMailbox(main, databaseURL, pairID, session.id, idToken)`;
     `useTransport(needsLocalNetwork = false) { pairing, callbacks -> FirebaseTransport(main, mailbox, session,
     callbacks.onConnected, callbacks.onMessage, callbacks.onDisconnected) }`. Construct a **new mailbox and session** inside each
     factory invocation. The current bridge still requires a saved explicit pairing.
   - Mac: construct `FirebaseRESTMailbox(databaseURL:pairID:sessionID:idToken:)` and
     `FirebaseConnection(mailbox:session:)`, then call `connect(using:)` after explicit pairing.
4. Add project-backed configuration and minimal pairing UI; select Firebase as the production
   default. Do not automatically leak traffic between cloud and LAN after a failure.
5. Implement coordinated fresh-session reconnect/rotation, phone/Mac sleep recovery, and backend
   deletion of sessions on unpair/revocation/expiry. Rule expiry blocks access but **does not delete
   data**; cleanup is required so encrypted mailbox values do not become retained history.
6. Verify live streaming, disconnects during snapshot/action/dismissal, expiry, token refresh,
   permission revocation, unpairing, large snapshots and phone-use suppression on physical devices.

These are real-time streams while the companion and Android listener can run. They do not
wake a terminated/suspended app. FCM/APNs wake delivery, background execution guarantees and
Doze behavior are separate production work; no push payloads or notification bodies are sent
through FCM here. Never claim a push arrived or a phone action succeeded based on database writes.

Official references checked October 28, 2026:
[RTDB REST and streaming](https://firebase.google.com/docs/reference/rest/database),
[REST authentication](https://firebase.google.com/docs/database/rest/auth),
[RTDB rules](https://firebase.google.com/docs/database/security/core-syntax),
[Android interactive state](https://developer.android.com/reference/android/os/PowerManager#isInteractive()),
[Android keyguard state](https://developer.android.com/reference/android/app/KeyguardManager#isKeyguardLocked()).
