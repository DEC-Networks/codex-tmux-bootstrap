#!/usr/bin/env bash
# Codex TMUX bootstrap behavioral tests
# Version: v26.7.14.1

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BOOTSTRAP="$ROOT/install.sh"
RUNNER="$ROOT/runner.sh"
TEST_ROOT="$(mktemp -d)"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_HOME="$TEST_ROOT/home"
TEST_LOG="$TEST_ROOT/calls.log"
RUNNER_URL="https://example.invalid/runner.sh"
pass=0
fail=0

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

ok() {
    pass=$((pass + 1))
    printf '  PASS  %s\n' "$1"
}

bad() {
    fail=$((fail + 1))
    printf '  FAIL  %s\n' "$1"
}

assert_log() {
    local pattern="$1" label="$2"
    if grep -Fq "$pattern" "$TEST_LOG"; then ok "$label"; else bad "$label"; fi
}

assert_no_log() {
    local pattern="$1" label="$2"
    if grep -Fq "$pattern" "$TEST_LOG"; then bad "$label"; else ok "$label"; fi
}

sha256_file() {
    sha256sum "$1" | awk '{print $1}'
}

mkdir -p "$FAKE_BIN" "$FAKE_HOME/.local/bin"

cat > "$FAKE_BIN/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail
output=""
url=""
while (( $# > 0 )); do
    case "$1" in
        -o|--output) output="$2"; shift 2 ;;
        https://*) url="$1"; shift ;;
        *) shift ;;
    esac
done
printf 'curl-url=%s\n' "$url" >> "$TEST_LOG"
case "$url" in
    https://example.invalid/runner.sh)
        cp "$TEST_RUNNER_SOURCE" "$output"
        ;;
    https://chatgpt.com/codex/install.sh)
        cat > "$output" <<'FAKE_OFFICIAL'
#!/bin/sh
printf 'official-non-interactive=%s\n' "${CODEX_NON_INTERACTIVE:-unset}" >> "$TEST_LOG"
if [ "${TEST_OFFICIAL_FAIL:-0}" = 1 ]; then exit 23; fi
exit 0
FAKE_OFFICIAL
        ;;
    *)
        printf 'unexpected URL: %s\n' "$url" >&2
        exit 88
        ;;
esac
FAKE_CURL

cat > "$FAKE_HOME/.local/bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then
    printf 'codex-version-check\n' >> "$TEST_LOG"
    printf 'codex-cli test\n'
    exit 0
fi
printf 'codex-launch=%s\n' "$*" >> "$TEST_LOG"
printf 'codex-path-head=%s\n' "${PATH%%:*}" >> "$TEST_LOG"
exit "${TEST_CODEX_STATUS:-0}"
FAKE_CODEX

cat > "$FAKE_BIN/tmux" <<'FAKE_TMUX'
#!/usr/bin/env bash
set -euo pipefail
subcommand="${1:-}"
shift || true
case "$subcommand" in
    has-session)
        printf 'tmux-has=%s\n' "$*" >> "$TEST_LOG"
        [[ "${TEST_TMUX_EXISTS:-0}" == 1 ]]
        ;;
    attach-session)
        printf 'tmux-attach=%s\n' "$*" >> "$TEST_LOG"
        ;;
    new-session)
        printf 'tmux-new=%s\n' "$*" >> "$TEST_LOG"
        while (( $# > 0 )); do
            if [[ "$1" == */runner.sh ]]; then
                TMUX='fake,1,0' "$@"
                exit $?
            fi
            shift
        done
        printf 'runner command not found in fake tmux arguments\n' >&2
        exit 90
        ;;
    *)
        printf 'unexpected tmux command: %s\n' "$subcommand" >&2
        exit 91
        ;;
esac
FAKE_TMUX

cat > "$FAKE_BIN/login-shell" <<'FAKE_SHELL'
#!/usr/bin/env bash
printf 'post-shell=%s\n' "$*" >> "$TEST_LOG"
exit 0
FAKE_SHELL

chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/tmux" "$FAKE_BIN/login-shell" \
    "$FAKE_HOME/.local/bin/codex"

run_env=(
    env
    "HOME=$FAKE_HOME"
    "PATH=$FAKE_BIN:/usr/bin:/bin"
    "SHELL=$FAKE_BIN/login-shell"
    "TEST_LOG=$TEST_LOG"
    "TEST_RUNNER_SOURCE=$RUNNER"
)

: > "$TEST_LOG"
TMUX='fake,1,0' "${run_env[@]}" "$RUNNER" -- --sandbox workspace-write >/dev/null
assert_log 'curl-url=https://chatgpt.com/codex/install.sh' 'uses OpenAI official installer URL'
assert_log 'official-non-interactive=1' 'runs official installer non-interactively'
assert_log 'codex-version-check' 'verifies the installed Codex executable'
assert_log 'codex-launch=--sandbox workspace-write' 'launches Codex and forwards arguments'
assert_log "codex-path-head=$FAKE_HOME/.local/bin" 'activates Codex PATH immediately'
assert_no_log 'tmux-new=' 'does not nest TMUX'
if grep -Fq "$FAKE_HOME/.local/bin" "$FAKE_HOME/.profile"; then
    ok 'persists Codex PATH'
else
    bad 'persists Codex PATH'
fi

: > "$TEST_LOG"
env -u TMUX "${run_env[@]}" "$RUNNER" >/dev/null
assert_log 'tmux-has=-t =codex-install' 'checks exact TMUX session name'
assert_log 'tmux-new=' 'creates TMUX from a direct shell'
assert_log 'official-non-interactive=1' 'installs after entering TMUX'
assert_log 'codex-launch=' 'launches Codex inside created TMUX session'
assert_log 'post-shell=-l' 'retains a login shell after Codex exits'

: > "$TEST_LOG"
TEST_TMUX_EXISTS=1 env -u TMUX "${run_env[@]}" "$RUNNER" >/dev/null
assert_log 'tmux-attach=-t =codex-install' 'attaches an existing exact TMUX session'
assert_no_log 'curl-url=' 'does not duplicate an active setup session'

: > "$TEST_LOG"
set +e
TEST_OFFICIAL_FAIL=1 TMUX='fake,1,0' "${run_env[@]}" "$RUNNER" >/dev/null 2>&1
rc=$?
set -e
if (( rc != 0 )); then ok 'propagates official installer failures'; else bad 'propagates official installer failures'; fi
assert_no_log 'codex-launch=' 'does not launch Codex after installer failure'

: > "$TEST_LOG"
runner_sha256="$(sha256_file "$RUNNER")"
"${run_env[@]}" \
    TMUX='fake,1,0' \
    CODEX_TMUX_TTY=/dev/null \
    CODEX_TMUX_RUNNER_URL="$RUNNER_URL" \
    CODEX_TMUX_RUNNER_SHA256="$runner_sha256" \
    bash < "$BOOTSTRAP" >/dev/null
assert_log 'curl-url=https://example.invalid/runner.sh' 'pipe-safe bootstrap downloads runner'
assert_log 'official-non-interactive=1' 'pipe-safe bootstrap executes verified runner'
assert_log 'codex-launch=' 'one-line route reaches Codex launch'

: > "$TEST_LOG"
set +e
"${run_env[@]}" \
    CODEX_TMUX_TTY=/dev/null \
    CODEX_TMUX_RUNNER_URL="$RUNNER_URL" \
    CODEX_TMUX_RUNNER_SHA256='0000000000000000000000000000000000000000000000000000000000000000' \
    bash < "$BOOTSTRAP" >/dev/null 2>&1
rc=$?
set -e
if (( rc != 0 )); then ok 'rejects a runner with the wrong checksum'; else bad 'rejects a runner with the wrong checksum'; fi
assert_no_log 'official-non-interactive=1' 'checksum failure blocks runner execution'

printf '\n  Result: %s passed, %s failed\n' "$pass" "$fail"
(( fail == 0 ))
