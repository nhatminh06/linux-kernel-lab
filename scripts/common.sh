#!/usr/bin/env bash
# Shared helpers for the linux-kernel-lab scripts.
# This file only defines functions/variables — it must be safe to `source`
# from any script without side effects. It never runs project actions itself.
set -euo pipefail

# --- colors (disabled when not attached to a terminal) ---------------------
if [[ -t 2 ]]; then
    _C_INFO=$'\033[1;34m'
    _C_WARN=$'\033[1;33m'
    _C_ERR=$'\033[1;31m'
    _C_RESET=$'\033[0m'
else
    _C_INFO="" _C_WARN="" _C_ERR="" _C_RESET=""
fi

log_info() {
    printf '%s[INFO]%s %s\n' "${_C_INFO}" "${_C_RESET}" "$*" >&2
}

log_warn() {
    printf '%s[WARN]%s %s\n' "${_C_WARN}" "${_C_RESET}" "$*" >&2
}

# Print an error and exit non-zero. Usage: log_fatal "message" [exit_code]
log_fatal() {
    local msg="$1"
    local code="${2:-1}"
    printf '%s[FATAL]%s %s\n' "${_C_ERR}" "${_C_RESET}" "${msg}" >&2
    exit "${code}"
}

# require_cmd <name> [name...] — fail with a clear message if any are missing.
require_cmd() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing+=("${cmd}")
        fi
    done
    if ((${#missing[@]} > 0)); then
        log_fatal "Missing required command(s): ${missing[*]}. Run scripts/check-dependencies.sh for guidance."
    fi
}

# require_dir <path> <description> — fail unless path is an existing directory.
require_dir() {
    local path="$1" desc="${2:-directory}"
    if [[ ! -d "${path}" ]]; then
        log_fatal "${desc} not found: ${path}"
    fi
}

# require_file <path> <description> — fail unless path is an existing file.
require_file() {
    local path="$1" desc="${2:-file}"
    if [[ ! -f "${path}" ]]; then
        log_fatal "${desc} not found: ${path}"
    fi
}

# abspath <path> — print an absolute path without requiring the target to exist.
abspath() {
    local path="$1"
    if [[ -d "${path}" ]]; then
        (cd "${path}" && pwd)
    else
        local dir base
        dir="$(dirname -- "${path}")"
        base="$(basename -- "${path}")"
        if [[ -d "${dir}" ]]; then
            printf '%s/%s\n' "$(cd "${dir}" && pwd)" "${base}"
        else
            printf '%s\n' "${path}"
        fi
    fi
}

# env_default <VAR_NAME> <default> — print the value of VAR_NAME if set and
# non-empty, otherwise print <default>. Does not modify the environment.
env_default() {
    local var_name="$1" default_value="$2"
    local value="${!var_name:-}"
    if [[ -n "${value}" ]]; then
        printf '%s\n' "${value}"
    else
        printf '%s\n' "${default_value}"
    fi
}

# repo_root — print the absolute path to the git repository root.
repo_root() {
    (cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
}

# Default output directory for generated artifacts (never Git-tracked).
readonly LAB_DEFAULT_WORKDIR="${LAB_WORKDIR:-$(repo_root)/.lab-build}"
