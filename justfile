# hhm-flutter task runner. Secrets are never loaded implicitly.
set dotenv-load := false

default:
    @just --list

bootstrap-platforms:
    flutter create --org org.hackerhousemedellin --project-name hhm_flutter --platforms android,ios,linux,macos,windows,web .

format:
    dart format lib test

format-check:
    dart format --output=none --set-exit-if-changed lib test

analyze:
    flutter analyze

test:
    flutter test

env-check:
    bash tool/check_encrypted_env.sh

check: format-check analyze test env-check

env-edit profile:
    sops edit --input-type dotenv --output-type dotenv env/enc/{{ profile }}.env.enc

env-rekey:
    sops updatekeys --yes --input-type dotenv env/enc/dev.env.enc
    sops updatekeys --yes --input-type dotenv env/enc/prod.env.enc

# Compile the encrypted PUBLIC configuration into a local app build without
# materializing plaintext. Platform runners must have been bootstrapped first.
run profile="dev":
    sops exec-env --input-type dotenv env/enc/{{ profile }}.env.enc 'flutter run --dart-define=HHM_API_BASE_URL="$HHM_API_BASE_URL" --dart-define=HHM_SHARED_AUTH_ISSUER="$HHM_SHARED_AUTH_ISSUER" --dart-define=HHM_SUPABASE_URL="$HHM_SUPABASE_URL" --dart-define=HHM_SUPABASE_PUBLISHABLE_KEY="$HHM_SUPABASE_PUBLISHABLE_KEY" --dart-define=HHM_OTEL_EXPORTER_OTLP_ENDPOINT="$HHM_OTEL_EXPORTER_OTLP_ENDPOINT" --dart-define=HHM_RELEASE_ENVIRONMENT="$HHM_RELEASE_ENVIRONMENT"'

zed-install:
    zed install

doctor:
    flutter --version
    just --version
    sops --version
    age --version
    nix --version
