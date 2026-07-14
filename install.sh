#!/usr/bin/env bash
# Codex TMUX bootstrap
# Version: v26.7.14.1

set -euo pipefail
umask 077

readonly BOOTSTRAP_VERSION="v26.7.14.1"
readonly DEFAULT_RUNNER_URL="https://raw.githubusercontent.com/DEC-Networks/codex-tmux-bootstrap/v26.7.14.1/runner.sh"
readonly DEFAULT_RUNNER_SHA256="aab8aec929791797171cd47ab70abf1741f3cae39ebc34e16a2f89693ced9556"

RUNNER_URL="${CODEX_TMUX_RUNNER_URL:-$DEFAULT_RUNNER_URL}"
RUNNER_SHA256="${CODEX_TMUX_RUNNER_SHA256:-$DEFAULT_RUNNER_SHA256}"
TTY_PATH="${CODEX_TMUX_TTY:-/dev/tty}"
RUNNER_FILE=""

error() {
    printf 'Codex TMUX bootstrap: %s\n' "$*" >&2
}

cleanup() {
    [[ -z "$RUNNER_FILE" ]] || rm -f "$RUNNER_FILE"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

sha256_file() {
    local path="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$path" | sed 's/^.*= //'
    else
        error "sha256sum, shasum, or openssl is required."
        return 1
    fi
}

command -v curl >/dev/null 2>&1 || {
    error "curl is required for the one-line bootstrap."
    exit 1
}

RUNNER_FILE="$(mktemp "${TMPDIR:-/tmp}/codex-tmux-runner.XXXXXX")"
curl --proto '=https' --tlsv1.2 -fsSL --output "$RUNNER_FILE" "$RUNNER_URL"

actual_sha256="$(sha256_file "$RUNNER_FILE")"
if [[ "$actual_sha256" != "$RUNNER_SHA256" ]]; then
    error "runner checksum verification failed."
    error "expected: $RUNNER_SHA256"
    error "actual:   $actual_sha256"
    exit 1
fi

if ! (: < "$TTY_PATH") 2>/dev/null; then
    error "an interactive terminal is required."
    exit 1
fi

printf 'Verified Codex TMUX runner %s. Starting...\n' "$BOOTSTRAP_VERSION" > "$TTY_PATH"
bash "$RUNNER_FILE" "$@" < "$TTY_PATH" > "$TTY_PATH" 2> "$TTY_PATH"
