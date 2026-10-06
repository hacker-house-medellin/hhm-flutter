# hhm-flutter

HHM’s Flutter application foundation for residents and visitors on Android,
iOS, Linux, macOS, Windows, and the web.

This initial public scaffold is runnable as a Flutter package and includes the
shared application shell, security-sensitive domain contracts, tests, CI,
encrypted build configuration, Nix tooling, and Zed package metadata. Native
runner files are the next focused change; see
[`docs/PLATFORM_BOOTSTRAP.md`](docs/PLATFORM_BOOTSTRAP.md).

## Current capabilities

- Dual-auth UI and adapter boundary for Supabase plus Shared Auth, with tokens
  hidden from UI/domain state.
- Separate visitor sign-in and sign-out QR actions. Payloads are backend-issued,
  rotate each minute, expire in at most 90 seconds, and redeem through one-time
  challenges.
- Strict managed-doorway codecs and an opt-in evidence gate for a signed BLE
  challenge plus separately keyed door-controller/NFC/UWB/local-network
  corroboration. The app uploads only a coarse signal bucket, and only an
  authenticated backend `accepted` decision can advance presence. Bluetooth
  is never identity proof, exact human location, or a door-unlock factor.
- Portable peer-to-peer Bluetooth contracts for explicit foreground peer
  selection, Shared Auth device-bound handshakes, encrypted replay-resistant
  envelopes, closed contact-card/plain-text-message/receipt JSON records, and
  official update-manifest discovery. JSON sharing defaults off and requires a
  negotiated capability plus an explicit local choice. Native transport and
  cryptographic adapters remain disabled until reviewed implementations land.
- Closed, privacy-safe Ores OTEL event schema with no arbitrary attributes or
  personal identifiers.
- SOPS + age ciphertext under `env/enc`, process-scoped `just` commands, and a
  Nix development shell. App builds contain public configuration only.

The transport and platform adapters are deliberately not faked. Until they are
connected to the generated `hhm-clients` interfaces, scan/proximity controls are
disabled and the UI cannot record a local event as authoritative.

## Develop

With Flutter 3.44.2 installed:

```sh
flutter pub get
just check
```

Or use the reproducible shell, which also supplies SOPS, age, `just`, and the
ORESoftware SOPS helper:

```sh
nix develop ./.nix
just doctor
just check
```

After reviewing the platform permission contract, generate all Flutter runners:

```sh
just bootstrap-platforms
```

An authorized operator can run a target with encrypted public build settings:

```sh
just run dev
```

See [`env/README.md`](env/README.md) before editing profiles. `--dart-define`
values are recoverable from app binaries, so encryption protects repository and
operator workflow—not secrets shipped to end users.

## Dependency model

`pubspec.yaml` controls Flutter dependencies. `.zpkg.toml` declares HHM source
dependencies (`hhm-clients`, `hhm-interfaces`, `hhm-sync`) and Shared Auth:

```sh
just zed-install
```

Zed materializes packages under `.vendor/.zed`. Do not commit that directory or
invent `.zpkg.lock`; commit a lock only after a real resolver succeeds.

The peer, P2P JSON, and managed-doorway contracts are pinned to
`hhm-interfaces` commit `ffc1df71d1d89202b431f4830cc2a43e4a451da3`.
Their exact source paths, digests, and byte-identical canonical fixtures are
recorded under [`protocol/`](protocol/README.md).

## Security and privacy

- QR and presence writes fail closed and become real only after backend
  acknowledgement.
- Presence challenges and scan challenges are short-lived and nonce-bound;
  servers must consume them exactly once and rate-limit attempts.
- Peer Bluetooth is transport only: it requires explicit foreground consent,
  Shared Auth device-bound verification, end-to-end encryption, expiry, replay
  rejection, and strict size/rate limits. It cannot authenticate from proximity,
  authorize a product action, report presence, or unlock a door.
- Peers can announce signed update metadata and, after explicit consent, carry
  only the closed v1 JSON record set. Duplicate keys, unknown properties,
  payload/schema mismatch, non-HTTPS links, expired records, arbitrary maps,
  HTML, credentials, and executables are rejected. Installation still obtains
  an official HTTPS artifact and verifies a pinned release key, anti-rollback
  counter, digest, byte count, and platform release signature; no peer bytes or
  executable code are loaded.
- Use system-browser PKCE, exact callback matching, and protected platform token
  storage for the dual-auth adapter.
- Do not log QR payloads, tokens, names, door/beacon identifiers, precise
  location, camera/audio content, or free-form backend errors.
- Camera recognition and conversation recording are not part of this app. They
  require separate consent, retention, access-control, and legal review.

The full trust model is in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). The
peer threat model and production gate are in
[`docs/BLUETOOTH_PEER_PROTOCOL.md`](docs/BLUETOOTH_PEER_PROTOCOL.md).

## License

MIT
