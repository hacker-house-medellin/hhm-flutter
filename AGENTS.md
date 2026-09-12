# AGENTS.md

Owner: `hacker-house-medellin`

This repository owns the HHM Flutter application shell for Android, iOS, Linux,
macOS, Windows, and the web.

## Non-negotiable boundaries

- Bluetooth, Nearby, geofences, and door beacons are optional presence evidence;
  they are never authentication factors and never unlock a door by themselves.
- Peer Bluetooth is foreground, explicitly selected, authenticated with
  Shared Auth device-bound keys, end-to-end encrypted, expiring, and
  replay-resistant. It carries no presence or door operation and never accepts
  peer-provided executable bytes.
- Rotating visitor QR payloads are issued and redeemed by the HHM backend. The
  client must not mint, sign, extend, or accept an expired payload locally.
- Shared Auth and Supabase credentials are exchanged through the backend-facing
  authorization flow. Never embed service-role keys, client secrets, signing
  keys, age private keys, or long-lived bearer tokens in an app build.
- Never log QR payloads, authorization material, beacon identifiers, precise
  location, names, faces, conversation content, or other personal data.
- Configuration committed to `env/enc` is SOPS ciphertext. Client binaries may
  receive only explicitly public configuration through `--dart-define`.
- Keep protocol changes compatible with `hhm-interfaces`; update the shared
  contract before depending on a new wire shape here.
- Pin peer compatibility to the exact `hhm-interfaces` commit recorded under
  `protocol/`, and keep its fixture byte-identical with a digest test.

Use focused pull requests, add tests with behavior changes, run `just check`,
and resolve conflicts semantically using both sides and relevant history.

## Functional programming conformance

This repository carries an FP conformance ratchet. Before you land a change:

```sh
python3 tools/fp-conformance/fp_conformance.py .
```

CI compares your findings against `tools/fp-conformance/budget.json` and fails
only when a rule's count *increases*. Do not raise the budget to get green — fix
the new violations. When you clear a class of violation, lower the budget in the
same commit with `--write-budget`.

The principles, the rule codes and the remedy for each are in `FP-GUIDELINES.md`.
