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
- Opt-in resident presence boundary for BLE plus an independent proximity
  signal. Automatic transitions require explicit consent and server approval;
  Bluetooth is never identity proof or a door-unlock factor.
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

## Security and privacy

- QR and presence writes fail closed and become real only after backend
  acknowledgement.
- Presence challenges and scan challenges are short-lived and nonce-bound;
  servers must consume them exactly once and rate-limit attempts.
- Use system-browser PKCE, exact callback matching, and protected platform token
  storage for the dual-auth adapter.
- Do not log QR payloads, tokens, names, door/beacon identifiers, precise
  location, camera/audio content, or free-form backend errors.
- Camera recognition and conversation recording are not part of this app. They
  require separate consent, retention, access-control, and legal review.

The full trust model is in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## License

MIT
