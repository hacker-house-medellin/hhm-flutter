# Application architecture

`hhm-flutter` is a client, not an authorization server. Its portable domain
layer refuses to make identity, visitor, or attendance decisions from local
sensor data.

## Trust flows

1. **Dual authentication.** The app starts an HHM-hosted authorization request
   in the system browser. The backend coordinates Supabase and Shared Auth,
   performs provider-token exchange, validates exact redirect/state/PKCE data,
   and returns an HHM-scoped session. UI state sees assurance and expiry only;
   tokens remain inside protected platform storage and the transport adapter.
2. **Visitor QR.** The backend issues a signed opaque payload for sign-in or
   sign-out with a window no longer than 90 seconds. The UI stops displaying it
   at expiry. Redemption uses a fresh server challenge and client nonce; only a
   server acknowledgement changes visitor state. Already-used and ambiguous
   writes fail closed.
3. **Resident presence.** A resident explicitly opts into permitted doors and
   chooses whether automatic transitions and approved background collection
   are allowed. A registered doorway broadcasts a signed, short-lived BLE
   challenge; a separately keyed door controller, NFC reader, UWB source, or
   local-network challenger corroborates it. The app submits those proofs with
   a backend nonce, coarse signal bucket, enrolled-device attestation/signature,
   policy version, and previous presence sequence. The backend verifies exact
   membership/device/door authorization, all registered keys and bindings,
   timing, rate limit, replay state, and atomic nonce consumption. Only its
   `accepted` decision updates attendance; ambiguous direction requires
   confirmation. This proves neither exact human location nor door access.
4. **Peer Bluetooth.** A person in the foreground explicitly selects one
   rotating peer offer. Shared Auth device-bound attestations and transcript
   signatures establish a short authenticated session; Bluetooth itself proves
   nothing about identity or permissions. Encrypted, expiring envelopes enforce
   replay, sequence, payload, size, and rate policy. Flutter accepts signed
   update metadata and, only after an additional explicit local choice, closed
   contact-card/plain-text-message/receipt JSON records. It never transfers
   installable bytes, presence, door actions, credentials, arbitrary JSON,
   executable content, or implicit files.
5. **Telemetry.** The client emits the typed `SafeTelemetryEvent` schema to an
   HHM Ores OTEL-compatible collector. There is no arbitrary attribute bag or
   free-form exception text, preventing accidental export of tokens, QR data,
   radio identifiers, location, names, or content.

## Dependency management

`pubspec.yaml` is authoritative for Dart/Flutter build dependencies. `.zpkg.toml`
declares organization-level source and contract edges to `hhm-clients`,
`hhm-interfaces`, `hhm-sync`, and `shared-auth-clients`. `zed install`
materializes them under `.vendor/.zed`; that directory is never committed.
Commit `.zpkg.lock` only when a real Zed resolver run produces it—never fabricate
a lock from repository metadata.

Wire schemas originate in `hhm-interfaces`. The peer-session, P2P JSON, and
managed-doorway contracts are pinned to immutable commit
`ffc1df71d1d89202b431f4830cc2a43e4a451da3`; exact paths, digests, and canonical
fixtures live under `protocol/`. This repository keeps the portable runtime
interfaces dependency-free so the scaffold can analyze and test before
generated Zed Dart targets are published. An adapter pull request should
replace local transport shapes with generated clients rather than fork or
privately extend the shared wire contract.

## Explicit exclusions

The Flutter app does not capture house cameras, recognize faces or activities,
or record conversations. Any future media feature requires a separate consent,
retention, access-control, legal, and abuse-case review before code or permissions
are added. No camera or microphone permission is part of the bootstrap contract.
