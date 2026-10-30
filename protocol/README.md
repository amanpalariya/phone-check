# Protocol v1

Signed-in devices pair through Firebase with a `pc2` code, then automatically
prefer direct TCP on port 47831 when reachable. Firebase carries encrypted `local_endpoint`
messages (`hosts`: up to eight literal private IPv4 addresses; `port`: 1024–65535) after a
cloud snapshot. Android validates addresses and mutually authenticates the local link before
switching; cloud listeners and notification writes stop while local. Failure resumes a fresh
Firebase session and silent snapshot. Unreachable local addresses retry after 30 seconds
without interrupting cloud delivery. See [Firebase sync](../firebase/README.md).

Signed-out users pair directly using `pc1|privateIPv4|port|base64url(secret)`.
This mode uses no Firebase account or messages, persists as a local-only pair after sign-in,
and reconnects to the saved address. It requires local-network permission and reachability;
a changed Mac address requires pairing again. The LAN test harness uses the same flow.
The Mac generates a random 256-bit secret, exposes it only during an explicit five-minute
pairing window, and accepts one persisted phone UUID. A new pairing secret invalidates
earlier codes. Treat a pairing code as a credential. No content is forwarded before authentication.

## Authentication and encryption

Every frame starts with a four-byte unsigned big-endian payload length. Maximum payload: 1 MiB (Mac unauthenticated frames: 4 KiB). Oversized, malformed, truncated, or unauthenticated frames close the connection. Connections have handshake and idle deadlines; the Mac caps candidates at four. UTF-8 JSON uses the fields in `Message` in `macos/Sources/PhoneCheckCore/Wire.swift`.

1. Mac sends plaintext `{type: "challenge", nonce: base64(serverRandom32)}`.
2. Android sends `{type: "authenticate", nonce: base64(clientRandom32), peer: UUID, proof: base64(clientProof)}`.
3. Mac verifies the proof, pairing window / saved peer, persists the peer, and sends plaintext `{type: "ready", proof: base64(serverProof)}`. Android verifies before sending content.
4. All subsequent JSON frames use AES-256-GCM, with independent keys and sequence counters in each direction.

`material = serverRandom32 || clientRandom32 || UTF8(peerUUID)`.

`derive(label) = HMAC-SHA256(secret, UTF8("phonecheck-v1/" + label + "/") || material)`.

Labels: `client-proof`, `server-proof`, `c2s`, `s2c`. Proofs use constant-time comparison. Each cipher starts at sequence zero; nonce is four zero bytes followed by an eight-byte big-endian sequence. Additional authenticated data is UTF-8 `phonecheck-v1`. Encrypted payload is ciphertext followed by the 16-byte authentication tag. Sequence is implicit, so replaying, skipping, or reordering an encrypted frame fails authentication. Both random nonces and directional derivation prevent key/nonce reuse across sessions. No commands or sequence state survive a disconnect.

This is a small application-layer PSK protocol using platform cryptographic primitives, not TLS. It does not provide forward secrecy and has not had an independent security audit. Changing transport should not change the active-state or dismissal rules. Android's `NotificationTransport` boundary separates socket lifecycle from `NotificationBridge`; macOS active-state reconciliation lives in `PhoneCheckCore`.

## Sync

- After authentication, Android sends encrypted `device_info` with `deviceName` (up to 128 characters) for the paired-phone label. Mac stores it with the pairing in Keychain; older phones without this message show “Android phone” and their pairing ID. This metadata does not affect notification reconciliation.

- Android sends `snapshot_begin`, bounded `snapshot_items` frames, then `snapshot_end`. Mac stages at most 1,000 notices / 32 MiB and commits atomically without alerts. The snapshot must complete within 20 seconds. Android serializes capture on its notification worker and queues snapshot frames together before live updates. The receiver also accepts the older single-frame `snapshot`; deploy both updated apps together.
- `upsert` carries `item`: `key`, `app`, `title`, `body`, `revision`, `dismissible`, `postedAt` (Unix milliseconds). The stable key is Android's notification key. Revision hashes content and opaque capability tokens, excluding automatic group assignment and icon pixels. Optional rich fields are declared in `NotificationModels.swift`: source PNG icon, kind, inbox lines, conversation messages, progress, JPEG preview, ongoing/group metadata, open capability, and action descriptors. Duplicate revisions do not alert again; changed revisions replace the same Mac alert identifier.
- `attention` carries `phoneInUse` and `sentAt` (Unix milliseconds). Android sends it before the snapshot and on screen/unlock changes. Each live `upsert` also includes these fields. Screen on and unlocked counts as phone use; Mac suppresses system alerts while retaining mirrored content. Old activity cannot replace newer activity. Live alert metadata older than 30 seconds or over 10 seconds in the future suppresses the alert. Suppressed alerts never replay on locking. Deploy both updated apps together because older Mac versions reject the new `attention` message.
- `device_status` carries `battery: {percentage: 0...100 | null, charging: boolean, powerSaving: boolean}` independently of notification reconciliation. `null` means no OS reading, never zero. Android observes system battery and PowerManager Battery Saver broadcasts, suppresses unchanged readings, and sends current status before every snapshot plus live changes within the authenticated session. A full battery on power uses `charging: true`. `powerSaving` reports active Battery Saver independently of charging; older messages without this field decode as unknown. No polling, extra permission, history, timestamps, or persisted battery data. The ordered session prevents replay; Mac clears battery state on disconnect and waits for a fresh reading. LAN and Firebase use the same payload. Deploy both updated apps together: older Mac versions reject `device_status`.
- `remove` carries `key` and clears both active state and any delivered/pending Mac alert. No history is stored.
- Disconnection clears the Mac's active state and alerts. Reconnect always requires a fresh snapshot. Unknown messages, unexpected snapshot ordering, and invalid notice sizes close the connection.
- Mac sends `ping` every 15 seconds; Android replies `pong`. Both sides time out an idle link after 45 seconds. Android retries with bounded exponential backoff. No wake lock or background-service exemption is requested; OS power restrictions can delay reconnection.

Text caps: app 256, title 2,048, body 8,192 characters. Snapshot batches target 400 KiB; every encrypted frame remains below 1 MiB. PNG icons are at most 12 KiB; JPEG previews at most 32 KiB. Image reads use bounded OS-granted content/resource URIs, never network URLs. Larger active sets disconnect rather than silently truncating. Notification bodies remain in process memory and the OS notification center, never application logs or a history store.

## Commands and dismissal

Mac sends `dismiss` with `command` (UUID), `key`, `revision`, `sentAt`, and `expiresAt` (Unix milliseconds, eight-second lifetime). UI remains pending. Android only acts while its listener is connected and snapshot sent. It rejects expired/future commands, excessive lifetimes, mismatched revisions, and non-clearable notifications before `cancelNotification(key)`.

A `result` includes `command` and `status`. `removed` requires a removal callback or a fresh active-notification read confirming absence. Other statuses include `expired`, `changed`, `blocked`, `access_denied`, `unconfirmed`, `unavailable`, `unsupported_input`, `requires_unlock`, and `failed`. Mac times out after ten seconds and never claims success on send. A late confirmation for an old revision cannot remove an updated notice. Phone removals clear the Mac copy regardless of which device initiated removal.

Mac categories deliberately omit `.customDismissAction`: ordinary Mac dismissal never sends a phone command. Explicit remote actions do require Mac authentication when locked. Ordinary Mac dismissal and banner expiry affect the Mac alone.

`action` and `open` share the command UUID, key, revision and expiry fields. `action` carries an opaque action ID and optional text (maximum 4,000 UTF-16 units). Android resolves against the fresh active notification and invokes its original PendingIntent. One text or fixed-choice RemoteInput is supported; data-only or multiple-input actions are rejected. A bounded ledger prevents duplicate side effects and returns cached results. `sent` means PendingIntent dispatch was accepted, not that the app completed an operation. No PendingIntent or arbitrary Intent fields cross the wire.
