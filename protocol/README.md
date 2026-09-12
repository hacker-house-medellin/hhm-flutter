# HHM peer protocol dependency

The canonical Bluetooth peer-session, closed JSON-record, and managed-doorway
wire contracts are owned by
[`hhm-interfaces`](https://github.com/hacker-house-medellin/hhm-interfaces) at
immutable commit
`ffc1df71d1d89202b431f4830cc2a43e4a451da3` (`hhm.p2p.v1`). The exact source
paths and SHA-256 digests are recorded in `CANONICAL_INTERFACE.json`.

The three files under `fixtures/v1/` are byte-for-byte copies of the canonical
fixtures. Compatibility tests parse their objects and verify their digests.
Fixture values are synthetic interoperability examples, not trusted
signatures, attestations, nonces, keys, or production release metadata.

The shared schema defines the cross-client vocabulary. This Flutter client is
deliberately stricter: signed update metadata follows its negotiated
capability, while contact cards, plain-text resident messages, and receipts
also require an explicit local foreground sharing choice. Those choices
default off. File manifests remain disabled. Strict decoding rejects unknown
properties, duplicate JSON keys, payload/schema mismatch, insecure links,
expired records, and records larger than 16 KiB before replay state is
committed.

Presence and door operations remain separate backend-mediated domains and are
never P2P payloads. The managed-doorway codec accepts only a short-lived signed
beacon challenge plus separately keyed corroboration, a backend nonce, an
enrolled-device attestation/signature, and coarse signal bucket. It carries no
raw RSSI, coordinates, scan inventory, or contact graph. Only an authenticated
backend `accepted` decision can advance authoritative presence; Bluetooth
discovery is untrusted transport evidence and never identity, authentication,
exact human location, or door-unlock authorization.

## Desktop interoperability

Flutter and `hhm-desktop-app.rs` must test against the same canonical schema,
commit, and fixture. An additive or breaking wire change starts in
`hhm-interfaces`, advances this immutable dependency record, and adds matching
fixtures and adversarial tests in both consumers. Neither client should create
a private extension to `hhm.p2p.v1`.
