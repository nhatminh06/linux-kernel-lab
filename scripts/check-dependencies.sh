#!/usr/bin/env bash
# Reports which build/debug/test dependencies are installed and exits
# non-zero if a dependency required by the other scripts is missing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--help]

Checks for the tools used by the scripts in this repository:
kernel build, BusyBox build, initramfs packaging, QEMU boot, GDB debugging,
and driver compilation.

This script never installs packages. See README.md for distribution-specific
install instructions (apt/dnf/pacman package names differ).
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

# name:required:used-by
DEPS=(
    "bash:required:all scripts"
    "make:required:kernel, BusyBox, driver builds"
    "gcc:required:kernel/BusyBox build (GCC path), driver build"
    "clang:optional:kernel/driver build with LLVM=1"
    "ld:required:linking the kernel and BusyBox"
    "bc:required:kernel build (kconfig arithmetic)"
    "bison:required:kernel build (kconfig parser)"
    "flex:required:kernel build (kconfig lexer)"
    "perl:required:kernel build scripts"
    "cpio:required:initramfs packaging"
    "gzip:required:initramfs compression"
    "qemu-system-x86_64:required:booting the kernel"
    "gdb:required:kernel debugging"
    "git:required:applying config-diff.patch, cloning sources"
)

missing_required=()
available=()
missing_optional=()

for entry in "${DEPS[@]}"; do
    IFS=':' read -r name level used_by <<<"${entry}"
    if command -v "${name}" >/dev/null 2>&1; then
        version="$("${name}" --version 2>&1 | head -n1 || true)"
        available+=("${name} (${version})")
    elif [[ "${level}" == "required" ]]; then
        missing_required+=("${name} — needed for: ${used_by}")
    else
        missing_optional+=("${name} — needed for: ${used_by}")
    fi
done

log_info "Available dependencies:"
for a in "${available[@]}"; do
    printf '  [ok] %s\n' "${a}"
done

if ((${#missing_optional[@]} > 0)); then
    log_warn "Missing optional dependencies:"
    for m in "${missing_optional[@]}"; do
        printf '  [--] %s\n' "${m}"
    done
fi

if ((${#missing_required[@]} > 0)); then
    log_warn "Missing required dependencies:"
    for m in "${missing_required[@]}"; do
        printf '  [!!] %s\n' "${m}"
    done
    echo >&2
    log_fatal "Install the missing packages for your distribution (see README.md § Dependencies) and re-run this script."
fi

log_info "All required dependencies are available."
