# Platform bootstrap contract

The repository commits the portable Flutter application, domain boundaries,
tests, and CI first. Native runner files are intentionally not hand-written:
Flutter owns those generated build graphs and they should be introduced in one
focused pull request after running:

```sh
just bootstrap-platforms
```

That creates runners for Android, iOS, Linux, macOS, Windows, and web while
preserving `lib/`, `test/`, and the repository configuration. Review every
generated file before committing it; do not accept generated signing material,
machine-local paths, or broad permissions.

## Permission review

- Android: request the narrow Bluetooth scan/connect permissions required by
  the supported OS level. Background location and background Bluetooth remain
  off until a documented product need and store-policy review exist.
- iOS: add accurate Bluetooth and location usage strings. Do not enable a
  background mode as a shortcut around lifecycle constraints.
- macOS: keep Bluetooth and location entitlements opt-in and code-sign the app
  through the release pipeline, never with repository credentials.
- Windows and Linux: start with foreground presence suggestions. Platform
  services for background transitions require separate threat modeling.
- Web: Web Bluetooth is unavailable or restricted in many browsers. Treat it
  as an optional foreground signal in a secure context, never a required path.

Every platform adapter implements the contracts under `lib/src/`. It must use a
system browser plus exact callback matching for dual auth, secure platform
storage for session material, a cryptographic RNG for scan/observation nonces,
and backend acknowledgement for all presence transitions.

Peer Bluetooth is a distinct foreground-only adapter. It must expose explicit
peer selection, implement authenticated key agreement through reviewed Shared
Auth device-bound verification, use platform-backed private keys plus reviewed
AEAD, and obey the portable replay, expiry, payload, size, and rate policy. It
must not reuse presence observations as authentication or carry bearer tokens.
Update adapters fetch only from official HTTPS origins after pinned release-key
and anti-rollback verification; peer-provided artifact bytes are never accepted.

The companion `hhm-desktop-app.rs` may later expose a C ABI consumed through
`dart:ffi`. Keep that bridge behind a Flutter interface so the native Rust UI
can complement the Flutter desktop UI without becoming a mandatory mobile or
web dependency.
