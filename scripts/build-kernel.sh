#!/usr/bin/env bash
# Builds a Linux kernel (bzImage + vmlinux) from a source tree that already
# exists on disk. This repository does not vendor kernel source; you must
# point this script at your own checkout (e.g. a `git clone` of
# https://git.kernel.org/.../linux.git at the tag you want, such as v6.10).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"
REPO_ROOT="$(repo_root)"

usage() {
    cat <<EOF
Usage: $(basename "$0") --source PATH [options]

Build a Linux kernel from an existing source tree. Produces vmlinux
(uncompressed, for GDB) and arch/x86/boot/bzImage (bootable, for QEMU)
in an out-of-tree build directory that is never Git-tracked.

Required:
  --source PATH        Path to a Linux kernel source tree (or set LINUX_SRC).

Options:
  --output PATH         Out-of-tree build dir, passed to make as O=
                         (or set KERNEL_BUILD_DIR). Default:
                         ${LAB_DEFAULT_WORKDIR}/kernel-build
  --config PATH          Copy this .config into the output dir before
                         building, instead of an existing/default config.
  --jobs, -j N            Parallel build jobs (default: \$(nproc)).
  --llvm                  Build with LLVM=1 (Clang/LLD instead of GCC/binutils).
                          This repository's chardev module was built this way
                          against a Clang-built distro kernel, but the kernel
                          itself was built with GCC (see kernel-build/README.md)
                          — LLVM=1 is opt-in here, not forced.
  --target NAME           make target (default: all, which builds both
                          vmlinux and bzImage).
  -h, --help              Show this help and exit.

Environment variable equivalents: LINUX_SRC, KERNEL_BUILD_DIR.

About kernel-build/config-diff.patch:
  This repository ships a diff showing how the tracked kernel's .config
  differs from a reference distro config. It is documentation of the
  options that were changed (e.g. CONFIG_HZ 1000 -> 300, BTF disabled),
  not a patch file meant to be mechanically applied with 'patch' — the
  two sides of the diff come from different machines' config paths. Read
  it with 'less kernel-build/config-diff.patch' or a diff viewer, and
  apply the equivalent options by hand with 'make menuconfig', or supply
  your own known-good config with --config.

This script never copies the built kernel into a Git-tracked directory.
EOF
}

SOURCE_DIR="$(env_default LINUX_SRC "")"
OUTPUT_DIR="$(env_default KERNEL_BUILD_DIR "${LAB_DEFAULT_WORKDIR}/kernel-build")"
CONFIG_PATH=""
JOBS="$(nproc 2>/dev/null || echo 4)"
USE_LLVM=0
TARGET="all"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) SOURCE_DIR="$2"; shift 2 ;;
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        --config) CONFIG_PATH="$2"; shift 2 ;;
        --jobs|-j) JOBS="$2"; shift 2 ;;
        --llvm) USE_LLVM=1; shift ;;
        --target) TARGET="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) log_fatal "Unknown argument: $1 (see --help)" ;;
    esac
done

[[ -n "${SOURCE_DIR}" ]] || { usage; log_fatal "Missing kernel source path: pass --source PATH or set LINUX_SRC."; }
require_dir "${SOURCE_DIR}" "Linux source directory"
SOURCE_DIR="$(abspath "${SOURCE_DIR}")"

# Sanity-check that this actually looks like a Linux kernel tree.
if [[ ! -f "${SOURCE_DIR}/Makefile" ]] || ! grep -q '^VERSION = ' "${SOURCE_DIR}/Makefile" 2>/dev/null \
    || [[ ! -f "${SOURCE_DIR}/init/main.c" ]] || [[ ! -d "${SOURCE_DIR}/arch/x86" ]]; then
    log_fatal "${SOURCE_DIR} does not look like a Linux kernel source tree (expected Makefile with VERSION=, init/main.c, arch/x86/)."
fi

require_cmd make
if ((USE_LLVM)); then
    require_cmd clang ld.lld
else
    require_cmd gcc ld
fi

mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="$(abspath "${OUTPUT_DIR}")"

# Guard against accidentally building into a Git-tracked path.
case "${OUTPUT_DIR}" in
    "${REPO_ROOT}"/*)
        log_fatal "Refusing to build into a path inside this repository (${OUTPUT_DIR}). Choose a location outside the repo, e.g. --output \$HOME/kernel-build."
        ;;
esac

if [[ -n "${CONFIG_PATH}" ]]; then
    require_file "${CONFIG_PATH}" "Kernel config"
    log_info "Copying ${CONFIG_PATH} -> ${OUTPUT_DIR}/.config"
    cp "${CONFIG_PATH}" "${OUTPUT_DIR}/.config"
elif [[ ! -f "${OUTPUT_DIR}/.config" ]]; then
    log_warn "No .config in ${OUTPUT_DIR} and no --config given."
    log_warn "Run '${SOURCE_DIR}/scripts/kconfig/... ' or 'make O=${OUTPUT_DIR} defconfig' yourself first, or pass --config PATH."
    log_fatal "No kernel configuration available; aborting before an unconfigured build wastes time."
fi

MAKE_ARGS=(-C "${SOURCE_DIR}" O="${OUTPUT_DIR}" -j "${JOBS}")
if ((USE_LLVM)); then
    MAKE_ARGS+=(LLVM=1)
fi

log_info "Building Linux (${TARGET}) from ${SOURCE_DIR}"
log_info "Output dir: ${OUTPUT_DIR}"
log_info "Jobs: ${JOBS}  LLVM=1: $((USE_LLVM))"
log_info "Command: make ${MAKE_ARGS[*]} ${TARGET}"

make "${MAKE_ARGS[@]}" "${TARGET}"

VMLINUX="${OUTPUT_DIR}/vmlinux"
BZIMAGE="${OUTPUT_DIR}/arch/x86/boot/bzImage"

echo
log_info "Build finished."
[[ -f "${VMLINUX}" ]] && echo "vmlinux: ${VMLINUX}"
[[ -f "${BZIMAGE}" ]] && echo "bzImage: ${BZIMAGE}"
if [[ ! -f "${VMLINUX}" && ! -f "${BZIMAGE}" ]]; then
    log_fatal "Neither vmlinux nor bzImage was produced; check the build log above."
fi
