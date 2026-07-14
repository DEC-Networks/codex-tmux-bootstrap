# Codex TMUX Bootstrap v26.7.14.1

Install or update Codex with OpenAI's official installer, enter TMUX, and start
Codex immediately.

```bash
curl -fsSL https://raw.githubusercontent.com/DEC-Networks/codex-tmux-bootstrap/main/install.sh | bash
```

That is the entire installation command.

Pinned release:

```bash
curl -fsSL https://raw.githubusercontent.com/DEC-Networks/codex-tmux-bootstrap/v26.7.14.1/install.sh | bash
```

## What It Does

1. Downloads a version-pinned runner and verifies its SHA-256 checksum.
2. Installs `tmux` when it is missing and a supported package manager is present.
3. Creates or attaches an exact `codex-install` TMUX session.
4. Downloads and runs OpenAI's official Codex installer.
5. Activates and persists the Codex command path.
6. Verifies the installed CLI and launches Codex for login or immediate work.
7. Leaves a login shell inside TMUX after Codex exits.

The wrapper adds no telemetry, opens no ports, and contains no credentials. It
does not mirror or modify Codex. Codex itself and OpenAI's installer remain
subject to OpenAI's terms and policies.

## Options

Pass runner options after `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/DEC-Networks/codex-tmux-bootstrap/main/install.sh | bash -s -- --session my-codex
```

Pass Codex arguments after a second `--`:

```bash
curl -fsSL https://raw.githubusercontent.com/DEC-Networks/codex-tmux-bootstrap/main/install.sh | bash -s -- -- -C "$PWD"
```

Configuration is available through `CODEX_TMUX_SESSION`,
`CODEX_TMUX_INSTALL_DEPS`, `CODEX_TMUX_KEEP_SHELL`, and the official installer's
`CODEX_RELEASE`, `CODEX_INSTALL_DIR`, and `CODEX_HOME` variables.

## Repackage

Distributors can host `runner.sh` themselves and set both
`CODEX_TMUX_RUNNER_URL` and `CODEX_TMUX_RUNNER_SHA256` before invoking
`install.sh`. The URL must use HTTPS and the checksum must match exactly.

The runner accepts an alternate official-compatible installer through
`CODEX_INSTALLER_URL`. The default and recommended source is OpenAI:
`https://chatgpt.com/codex/install.sh`.

## Trust Model

The short command trusts this repository's bootstrap, which then pins and
checksums the full runner. The runner downloads OpenAI's installer over HTTPS;
OpenAI's installer verifies the downloaded Codex release archive against
published SHA-256 digests.

For an immutable bootstrap, replace `main` in the command with a release tag.

## Test

```bash
./tests/test.sh
```

The tests replace `curl`, `tmux`, and `codex` with local fakes. They do not
create a real TMUX session or install software.

This is a community wrapper and is not affiliated with or endorsed by OpenAI.
