#!/usr/bin/env bash
# shell_config.sh — source me from other scripts
# Helpers to persist env vars / lines in the user's shell config file.
# Supports bash, zsh and fish.

# Resolve the shell config path for the current login shell.
get_shell_rc() {
    if [ -n "${SHELL_RC_FILE:-}" ]; then
        printf '%s\n' "$SHELL_RC_FILE"
        return
    fi

    local shell
    if command -v getent &>/dev/null; then
        shell="$(getent passwd "$(id -u)" | cut -d: -f7)"
    fi
    shell="${shell:-${SHELL:-/bin/bash}}"

    case "$shell" in
        *fish) printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish" ;;
        *zsh)  printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" ;;
        *)     printf '%s\n' "${HOME}/.bashrc" ;;
    esac
}

# Return the login shell name (fish, zsh, bash, ...).
get_shell_name() {
    local shell
    if command -v getent &>/dev/null; then
        shell="$(getent passwd "$(id -u)" | cut -d: -f7)"
    fi
    shell="${shell:-${SHELL:-bash}}"
    basename "$shell"
}

# Append `export NAME="value"` (bash/zsh) or `set -gx NAME "value"` (fish)
# to the shell config file, unless it is already present.
append_env_export() {
    local name="$1"
    local value="$2"
    local rc line needle
    rc="$(get_shell_rc)"

    case "$(basename "$rc")" in
        config.fish)
            needle="set -gx ${name}"
            line="set -gx ${name} \"${value}\""
            ;;
        *)
            needle="${name}="
            line="export ${name}=\"${value}\""
            ;;
    esac

    if ! grep -qF "$needle" "$rc" 2>/dev/null; then
        mkdir -p "$(dirname "$rc")"
        printf '\n%s\n' "$line" >> "$rc"
    fi
}

# Append a raw line to the shell config file, unless it is already present.
append_shell_line() {
    local line="$1"
    local rc
    rc="$(get_shell_rc)"

    if ! grep -qF "$line" "$rc" 2>/dev/null; then
        mkdir -p "$(dirname "$rc")"
        printf '%s\n' "$line" >> "$rc"
    fi
}