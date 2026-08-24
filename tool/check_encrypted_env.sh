#!/usr/bin/env bash
set -euo pipefail

fail=0
note() {
  echo "env-check: $1" >&2
  fail=1
}

for rule in '.env' '*.env' '**/*.env' 'env/dec/'; do
  grep -qxF "$rule" .gitignore || note "missing .gitignore rule: $rule"
done

tracked_plaintext="$(
  git ls-files \
    | grep -E '(^|/)\.env$|(^|/)\.env\.[^/]*$|(^|/)env/dec/' \
    | grep -vE '\.(example|sample|template)$' \
    || true
)"
if [[ -n "$tracked_plaintext" ]]; then
  note "plaintext dotenv material is tracked: $tracked_plaintext"
fi

private_keys="$(
  git ls-files \
    | grep -E '\.(agekey|age-key)$|(^|/)keys\.txt$|sops-private' \
    || true
)"
if [[ -n "$private_keys" ]]; then
  note "possible age private-key material is tracked: $private_keys"
fi

for file in env/enc/dev.env.enc env/enc/prod.env.enc; do
  [[ -f "$file" ]] || {
    note "missing approved ciphertext: $file"
    continue
  }
  grep -q 'ENC\[AES256_GCM' "$file" || note "$file is not SOPS ciphertext"
  grep -q '^sops_mac=' "$file" || note "$file has no SOPS MAC"
  recipients="$(grep -c 'map_recipient' "$file" || true)"
  if [[ "$recipients" -lt 2 ]]; then
    note "$file has fewer than two age recipients"
  fi
done

for file in .env.example env/enc/dev.env.enc env/enc/prod.env.enc; do
  forbidden="$(
    grep -Ei '^(SUPABASE_SERVICE_ROLE|.*_SECRET|.*PRIVATE_KEY|DATABASE_URL)=' "$file" \
      || true
  )"
  if [[ -n "$forbidden" ]]; then
    note "$file contains a server-only variable name"
  fi
done

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo 'env-check: ciphertext, recipient redundancy, and client-only keys verified'
