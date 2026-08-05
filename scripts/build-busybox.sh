#!/usr/bin/env bash
# Builds a statically-linked BusyBox and installs it into a staging
# directory, from an existing BusyBox source tree (not vendored in this repo).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"
REPO_ROOT="$(repo_root)"

usage() {
    cat <<EOF
Usage: $(basename "$0") --source PATH [options]

Build a statically-linked BusyBox from an existing source tree and install
it into a staging directory (never the host system).

Required:
  --source PATH          Path to a BusyBox source tree (or set BUSYBOX_SRC).
                          e.g. a checkout of https://git.busybox.net/busybox

Options:
  --install-dir PATH     Staging directory for 'make install'
                          (or set BUSYBOX_INSTALL_DIR). Default:
                          ${LAB_DEFAULT_WORKDIR}/busybox-install
  --jobs, -j N            Parallel build jobs (default: \$(nproc)).
  -h, --help              Show this help and exit.

Environment variable equivalents: BUSYBOX_SRC, BUSYBOX_INSTALL_DIR.

Behavior:
  - Runs 'make defconfig' only if no .config is already present in the
    source tree, so a config you've customized is left alone.
  - Forces CONFIG_STATIC=y (static build) via 'make oldconfig', since the
    initramfs has no dynamic linker or shared libraries available at boot.
  - Installs with 'make CONFIG_PREFIX=<install-dir> install', which is
    BusyBox's own staging mechanism — it never touches /bin or /usr on
    the host.
  - Verifies the resulting busybox binary is actually static and fails
    with a clear explanation if it is not (a dynamically-linked busybox
    will not run in the initramfs, which has no loader or libc).
EOF
}

SOURCE_DIR="$(env_default BUSYBOX_SRC "")"
INSTALL_DIR="$(env_default BUSYBOX_INSTALL_DIR "${LAB_DEFAULT_WORKDIR}/busybox-install")"
JOBS="$(nproc 2>/dev/null || echo 4)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) SOURCE_DIR="$2"; shift 2 ;;
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        --jobs|-j) JOBS="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) log_fatal "Unknown argument: $1 (see --help)" ;;
    esac
done

[[ -n "${SOURCE_DIR}" ]] || { usage; log_fatal "Missing BusyBox source path: pass --source PATH or set BUSYBOX_SRC."; }
require_dir "${SOURCE_DIR}" "BusyBox source directory"
SOURCE_DIR="$(abspath "${SOURCE_DIR}")"

if [[ ! -f "${SOURCE_DIR}/include/applets.h" ]] || ! grep -qi 'busybox' "${SOURCE_DIR}/Makefile" 2>/dev/null; then
    log_fatal "${SOURCE_DIR} does not look like a BusyBox source tree (expected include/applets.h and a Makefile mentioning BusyBox)."
fi

require_cmd make gcc

mkdir -p "${INSTALL_DIR}"
INSTALL_DIR="$(abspath "${INSTALL_DIR}")"
case "${INSTALL_DIR}" in
    "${REPO_ROOT}"/*)
        log_fatal "Refusing to install into a path inside this repository (${INSTALL_DIR}). Choose a location outside the repo."
        ;;
esac

pushd "${SOURCE_DIR}" >/dev/null

if [[ ! -f .config ]]; then
    log_info "No .config found; running 'make defconfig'."
    make defconfig
else
    log_info "Using existing .config in ${SOURCE_DIR} (not overwriting it)."
fi

if grep -q '^# CONFIG_STATIC is not set' .config; then
    log_info "Enabling CONFIG_STATIC=y for a static build (required for the initramfs)."
    sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
elif ! grep -q '^CONFIG_STATIC=y' .config; then
    echo 'CONFIG_STATIC=y' >>.config
fi
yes "" | make oldconfig >/dev/null

log_info "Building BusyBox with ${JOBS} job(s)."
make -j "${JOBS}"

log_info "Installing into staging directory: ${INSTALL_DIR}"
make CONFIG_PREFIX="${INSTALL_DIR}" install

popd >/dev/null

BUSYBOX_BIN="${INSTALL_DIR}/bin/busybox"
require_file "${BUSYBOX_BIN}" "Installed busybox binary"

if command -v file >/dev/null 2>&1; then
    if ! file "${BUSYBOX_BIN}" | grep -qi 'statically linked'; then
        log_fatal "Built busybox does not appear to be statically linked (needed for the initramfs, which has no dynamic linker). Check that your toolchain supports static linking (e.g. install glibc-static / musl) and retry."
    fi
else
    log_warn "'file' command not available; skipping static-link verification."
fi

log_info "BusyBox staged at: ${INSTALL_DIR}"
echo "${INSTALL_DIR}"
