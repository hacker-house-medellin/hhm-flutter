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
   chooses whether automatic transitions are allowed. A short-lived server
   challenge binds BLE plus an independent nearby signal to one attempt. The
   backend validates the signed session, timing, device binding, rate limit, and
   nonce consumption. This updates attendance only; it never unlocks a door or
   establishes identity.
4. **Peer Bluetooth.** A person in the foreground explicitly selects one
   rotating peer offer. Shared Auth device-bound attestations and transcript
   signatures establish a short authenticated session; Bluetooth itself proves
   nothing about identity or permissions. Encrypted, expiring envelopes enforce
   replay, sequence, payload, size, and rate policy. Flutter currently accepts
   signed update metadata only. It never transfers installable bytes, presence,
   door actions, credentials, private content, or arbitrary files.
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

Wire schemas originate in `hhm-interfaces`. The peer-session contract is pinned
to immutable commit `f694bc9b58907db918f0449b5d04a5763f8fa745`; exact paths,
digests, and the canonical fixture live under `protocol/`. This repository keeps
the portable runtime interfaces dependency-free so the scaffold can analyze and
test before generated Zed Dart targets are published. An adapter pull request
should replace local transport shapes with generated clients rather than fork
or privately extend the shared wire contract.

## Explicit exclusions

The Flutter app does not capture house cameras, recognize faces or activities,
or record conversations. Any future media feature requires a separate consent,
retention, access-control, legal, and abuse-case review before code or permissions
are added. No camera or microphone permission is part of the bootstrap contract.
