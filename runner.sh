#!/usr/bin/env bash
# Codex TMUX runner
# Version: v26.7.14.1

set -euo pipefail
umask 077

readonly RUNNER_VERSION="v26.7.14.1"
OFFICIAL_INSTALLER_URL="${CODEX_INSTALLER_URL:-https://chatgpt.com/codex/install.sh}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_PATH="$SCRIPT_DIR/${BASH_SOURCE[0]##*/}"
START_DIR="$PWD"
TMUX_SESSION_NAME="${CODEX_TMUX_SESSION:-codex-install}"
INSTALL_DEPENDENCIES="${CODEX_TMUX_INSTALL_DEPS:-1}"
KEEP_SHELL="${CODEX_TMUX_KEEP_SHELL:-1}"
TMUX_CHILD=0
APT_UPDATED=0
DOWNLOADED_INSTALLER=""
CODEX_ARGS=()

usage() {
    cat <<'USAGE'
Usage: runner.sh [OPTIONS] [-- CODEX_ARGUMENTS...]

Install or update Codex with OpenAI's official installer and launch it inside
TMUX.

Options:
  --session NAME       TMUX session name (default: codex-install)
  --no-install-deps    Do not install missing curl or tmux packages
  --no-shell           Close a wrapper-created TMUX pane after Codex exits
  -h, --help           Show this help

Environment:
  CODEX_TMUX_SESSION       Default TMUX session name
  CODEX_TMUX_INSTALL_DEPS  Set to 0 to disable dependency installation
  CODEX_TMUX_KEEP_SHELL    Set to 0 to close the pane after Codex exits
  CODEX_INSTALLER_URL      Alternate HTTPS Codex installer URL

OpenAI installer variables such as CODEX_RELEASE, CODEX_INSTALL_DIR, and
CODEX_HOME pass through unchanged.
USAGE
}

info() {
    printf '  %s\n' "$*"
}

error() {
    printf '  ERROR: %s\n' "$*" >&2
}

enabled() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

cleanup() {
    if [[ -n "$DOWNLOADED_INSTALLER" ]]; then
        rm -f "$DOWNLOADED_INSTALLER"
        DOWNLOADED_INSTALLER=""
    fi
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

run_as_root() {
    if (( EUID == 0 )); then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        error "Installing dependencies requires root or sudo."
        return 1
    fi
}

install_package() {
    local package="$1"

    if ! enabled "$INSTALL_DEPENDENCIES"; then
        error "Missing '$package'. Install it manually or enable dependency installation."
        return 1
    fi

    info "Installing required package: $package"
    if command -v apt-get >/dev/null 2>&1; then
        if (( APT_UPDATED == 0 )); then
            run_as_root apt-get update || return 1
            APT_UPDATED=1
        fi
        run_as_root apt-get install -y "$package"
    elif command -v dnf >/dev/null 2>&1; then
        run_as_root dnf install -y "$package"
    elif command -v yum >/dev/null 2>&1; then
        run_as_root yum install -y "$package"
    elif command -v apk >/dev/null 2>&1; then
        run_as_root apk add "$package"
    elif command -v pacman >/dev/null 2>&1; then
        run_as_root pacman -Sy --needed --noconfirm "$package"
    elif command -v brew >/dev/null 2>&1; then
        brew install "$package"
    else
        error "No supported package manager found. Install '$package' and retry."
        return 1
    fi
}

ensure_command() {
    local command_name="$1"
    local package_name="$2"

    command -v "$command_name" >/dev/null 2>&1 && return 0
    install_package "$package_name" || return 1
    command -v "$command_name" >/dev/null 2>&1 || {
        error "The '$command_name' command is still unavailable."
        return 1
    }
}

normalize_session_name() {
    TMUX_SESSION_NAME="${TMUX_SESSION_NAME//[^A-Za-z0-9_-]/-}"
    [[ -n "$TMUX_SESSION_NAME" ]] || TMUX_SESSION_NAME="codex-install"
}

append_forwarded_environment() {
    local name value
    local -a names=(
        CODEX_RELEASE
        CODEX_INSTALL_DIR
        CODEX_HOME
        CODEX_INSTALLER_URL
    )

    FORWARDED_ENV=("PATH=$PATH" "HOME=$HOME")
    [[ -n "${SHELL:-}" ]] && FORWARDED_ENV+=("SHELL=$SHELL")
    for name in "${names[@]}"; do
        value="${!name:-}"
        [[ -n "$value" ]] && FORWARDED_ENV+=("$name=$value")
    done
    return 0
}

enter_tmux() {
    local -a tmux_command

    ensure_command tmux tmux || return 1
    normalize_session_name

    if tmux has-session -t "=$TMUX_SESSION_NAME" 2>/dev/null; then
        info "Attaching existing TMUX session: $TMUX_SESSION_NAME"
        exec tmux attach-session -t "=$TMUX_SESSION_NAME"
    fi

    append_forwarded_environment
    info "Opening TMUX session: $TMUX_SESSION_NAME"
    tmux_command=(
        tmux new-session
        -s "$TMUX_SESSION_NAME"
        -c "$START_DIR"
        env
        "${FORWARDED_ENV[@]}"
        "$SCRIPT_PATH"
        --_tmux-child
        --session "$TMUX_SESSION_NAME"
    )
    enabled "$INSTALL_DEPENDENCIES" || tmux_command+=(--no-install-deps)
    enabled "$KEEP_SHELL" || tmux_command+=(--no-shell)
    if (( ${#CODEX_ARGS[@]} > 0 )); then
        tmux_command+=(-- "${CODEX_ARGS[@]}")
    fi
    exec "${tmux_command[@]}"
}

select_profile() {
    case "${SHELL:-/bin/bash}" in
        */bash) printf '%s\n' "$HOME/.bashrc" ;;
        */zsh)  printf '%s\n' "$HOME/.zshrc" ;;
        *)      printf '%s\n' "$HOME/.profile" ;;
    esac
}

ensure_persistent_path() {
    local bin_dir="$1"
    local profile path_assignment

    for profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [[ -f "$profile" ]] && grep -Fq "$bin_dir" "$profile"; then
            return 0
        fi
    done

    profile="$(select_profile)"
    printf -v path_assignment 'export PATH=%q:"$PATH"' "$bin_dir"
    {
        printf '\n# Codex TMUX Bootstrap PATH (%s)\n' "$RUNNER_VERSION"
        printf '%s\n' "$path_assignment"
    } >> "$profile" || {
        error "Could not persist the Codex PATH in $profile."
        return 1
    }
    info "Added the Codex command directory to $profile"
}

download_official_installer() {
    ensure_command curl curl || return 1

    DOWNLOADED_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/codex-tmux.XXXXXX")" || {
        error "Could not create a temporary installer file."
        return 1
    }

    info "Downloading OpenAI's official Codex installer..."
    if ! curl --proto '=https' --tlsv1.2 -fsSL \
        --output "$DOWNLOADED_INSTALLER" "$OFFICIAL_INSTALLER_URL"; then
        error "Could not download $OFFICIAL_INSTALLER_URL"
        return 1
    fi

    [[ -s "$DOWNLOADED_INSTALLER" ]] || {
        error "The installer download was empty."
        return 1
    }
}

install_and_launch_codex() {
    local bin_dir bin_path codex_status

    download_official_installer || return 1

    info "Running OpenAI's official Codex installer..."
    if ! CODEX_NON_INTERACTIVE=1 sh "$DOWNLOADED_INSTALLER"; then
        error "OpenAI's Codex installer failed."
        return 1
    fi
    cleanup

    bin_dir="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
    bin_path="$bin_dir/codex"
    case ":$PATH:" in
        *":$bin_dir:"*) ;;
        *) export PATH="$bin_dir:$PATH" ;;
    esac
    hash -r

    ensure_persistent_path "$bin_dir" || return 1
    [[ -x "$bin_path" ]] || {
        error "The installer completed, but $bin_path is not executable."
        return 1
    }

    info "Installed Codex version:"
    "$bin_path" --version || {
        error "The installed Codex executable did not pass its version check."
        return 1
    }

    info "Launching Codex inside TMUX from $START_DIR"
    "$bin_path" "${CODEX_ARGS[@]}"
    codex_status=$?
    return "$codex_status"
}

main() {
    local rc=0

    while (( $# > 0 )); do
        case "$1" in
            -h|--help)
                usage
                return 0
                ;;
            --session)
                [[ $# -ge 2 ]] || {
                    error "--session requires a name."
                    return 2
                }
                TMUX_SESSION_NAME="$2"
                shift 2
                ;;
            --no-install-deps)
                INSTALL_DEPENDENCIES=0
                shift
                ;;
            --no-shell)
                KEEP_SHELL=0
                shift
                ;;
            --_tmux-child)
                TMUX_CHILD=1
                shift
                ;;
            --)
                shift
                CODEX_ARGS=("$@")
                break
                ;;
            *)
                error "Unknown argument: $1"
                usage >&2
                return 2
                ;;
        esac
    done

    if [[ -z "${TMUX:-}" ]] && (( TMUX_CHILD == 0 )); then
        enter_tmux
        return $?
    fi

    if install_and_launch_codex; then
        rc=0
    else
        rc=$?
    fi

    if (( TMUX_CHILD == 1 )) && enabled "$KEEP_SHELL"; then
        printf '\n  Codex installer exited with status %s.\n' "$rc"
        info "The TMUX shell remains open for continued work or recovery."
        exec "${SHELL:-/bin/bash}" -l
    fi

    return "$rc"
}

main "$@"
