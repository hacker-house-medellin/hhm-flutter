# Encrypted build configuration

`env/enc/dev.env.enc` and `env/enc/prod.env.enc` are the only tracked
environment profiles. They are SOPS-encrypted dotenv files with three public
age recipients. Plaintext is never committed and this repository deliberately
does not provide a recipe that decrypts to disk.

Flutter compile-time values are public even when their source file is encrypted:
anyone can inspect a shipped app and recover every `--dart-define`. Therefore
these profiles may contain only public endpoints, the Supabase publishable key,
and non-sensitive release labels. They must never contain service-role keys,
OAuth client secrets, signing keys, database URLs, authenticated OTLP headers,
age private keys, or bearer tokens.

## Setup

Enter the reproducible development shell:

```sh
nix develop ./.nix
just doctor
```

An operator with an age private key can then edit a profile without creating a
plaintext file:

```sh
just env-edit dev
just env-rekey
just env-check
```

To run an already-bootstrapped Flutter target with a profile, use `just run
dev`. SOPS decrypts into the child process environment, and the recipe passes
only the allowlisted public variables as Dart defines.

## Key custody

The age values in `.sops.yaml` are public recipients. Their private halves live
outside Git on operator machines or in offline recovery custody. Removing a
recipient does not revoke values they previously decrypted; rotate the affected
upstream credentials whenever access is removed.

CI runs `just env-check` without a private key. It verifies ciphertext markers,
the SOPS MAC, recipient redundancy, ignore rules, and server-only variable names.
