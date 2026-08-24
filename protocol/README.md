# HHM peer protocol dependency

The canonical Bluetooth peer-session wire contract is owned by
[`hhm-interfaces`](https://github.com/hacker-house-medellin/hhm-interfaces) at
immutable commit
`f694bc9b58907db918f0449b5d04a5763f8fa745` (`hhm.p2p.v1`). The exact source
paths and SHA-256 digests are recorded in `CANONICAL_INTERFACE.json`.

`fixtures/v1/peer-session.json` is a byte-for-byte copy of the canonical
fixture. Compatibility tests parse every object and verify its digest. Fixture
values are synthetic interoperability examples, not trusted signatures,
attestations, nonces, keys, or production release metadata.

The shared schema defines the cross-client vocabulary. This Flutter client is
deliberately stricter: its peer payload policy enables only encrypted,
signed-update-manifest metadata. The other canonical payload types remain
representable for compatibility but are denied by the app policy.

Presence and door operations are separate backend-mediated domains. There is
no presence, authorization, door-unlock, or executable payload in this peer
protocol. Bluetooth discovery is untrusted transport evidence and never an
identity or authentication result.

## Desktop interoperability

Flutter and `hhm-desktop-app.rs` must test against the same canonical schema,
commit, and fixture. An additive or breaking wire change starts in
`hhm-interfaces`, advances this immutable dependency record, and adds matching
fixtures and adversarial tests in both consumers. Neither client should create
a private extension to `hhm.p2p.v1`.
