# Bluetooth peer protocol

This document is the Flutter app policy layered over the canonical
`hhm.p2p.v1` wire contract in `hhm-interfaces` commit
`ffc1df71d1d89202b431f4830cc2a43e4a451da3`. The exact source paths, fixtures,
and digests are under `protocol/`.

## Security boundary

Bluetooth is an untrusted, lossy transport. Discovery proves only that a radio
advertisement was observed. It is never identity, authentication,
authorization, assurance, attendance, door-unlock approval, or automatic
trust. Presence remains a separate backend-mediated flow.

A peer exchange may start only while the app is in the foreground, after the
person explicitly chooses one rotating offer and a bounded capability set.
Consent is scoped to that offer and foreground lifecycle, expires within two
minutes, and cannot be silently carried into a later scan.

Shared Auth supplies the reviewed verifier for device-bound attestations and
handshake transcript signatures. The app does not exchange bearer or service
tokens, refresh tokens, cookies, passwords, OTPs, private keys, provider
credentials, or product permissions. Authentication establishes the remote
device key for a short session; it does not grant an HHM product role.
Invalid proof and unavailable/degraded verification are distinct typed outcomes,
but both fail closed without establishing a peer session.

Each accepted handshake selects at least one capability. Offer IDs, challenge
nonces, session IDs, message IDs, envelope nonces, and monotonically increasing
sequences are replay-checked and expire. Unknown protocol versions, fields,
capabilities, payloads, key IDs, late messages, clock rollback, duplicates, and
rate or size violations fail closed.

Envelope preflight checks and charges the bounded rate budget without advancing
replay state. The message ID, nonce, and sequence are committed atomically only
after AEAD authentication and strict payload decoding succeed. Invalid
ciphertext therefore cannot poison the sequence window, while two concurrent
valid receives still yield exactly one accepted commit.

## Payload policy

`hhm-interfaces` defines an allowlist of interoperable payload type names and
closed JSON schemas. The Flutter policy permits `hhm.update-manifest.v1` after
an authenticated, end-to-end-encrypted session negotiated `update_manifest`.
Bounded contact cards, plain-text resident messages, and receipts additionally
require their negotiated capability plus an explicit local sharing choice that
defaults off. File manifests and every unknown type remain disabled.

The JSON decoder rejects duplicate object keys before `jsonDecode`, unknown or
missing properties, envelope/schema mismatch, control characters, non-HTTPS
website fields, expired or over-ten-minute records, and plaintext larger than
16 KiB. Message text is rendered only as text. Arbitrary maps, HTML execution,
dynamic telemetry attributes, and implicit file transfer are not extension
mechanisms. Replay state is committed only after AEAD authentication and this
strict schema validation both succeed.

Peer exchange must never carry raw conversation, camera, microphone, face,
activity, precise-location, beacon, visitor QR, password, token, secret,
arbitrary-file, executable, script, or dynamic-code content. There are no
presence or door-operation payloads.

The portable policy further limits decrypted update metadata to 8 KiB, binds
each envelope to its authenticated session and sender key, limits the envelope
to 30 seconds at use time, and applies bounded per-scope sliding-window rates.
Native adapters may impose lower ceilings but never exceed the canonical schema
or portable policy.

## Update discovery

A peer can announce signed metadata only. It cannot supply installable bytes or
an executable load path. A candidate manifest must:

- target `hhm-flutter`, the current platform and channel;
- increase the installed anti-rollback counter;
- use an allowlisted official HTTPS origin with no user info, query, or fragment;
- fit the configured artifact-size and publication-time bounds; and
- verify against the pinned HHM release-signing public key.

After verification, the platform update adapter independently downloads the
artifact from the official origin, checks the exact byte count and SHA-256,
revalidates the signed manifest, and requires the platform's normal signature,
notarization, or store verification. It never installs peer-provided bytes,
loads peer code, or bypasses platform release controls.

## Production gate and interoperability

The repository currently provides portable contracts and adversarial tests,
not a production radio or cryptographic adapter. Peer exchange remains disabled
until reviewed native BLE transports, cryptographic RNG and AEAD, official
Shared Auth device-attestation verification, protected device-key storage, and
the real pinned release public key are wired on each platform.

Flutter and `hhm-desktop-app.rs` use the same pinned canonical schema and fixture
described in `protocol/README.md`. Wire changes are made in `hhm-interfaces`
first and then adopted at a reviewed immutable commit by both clients.
