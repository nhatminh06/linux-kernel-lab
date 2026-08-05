#!/usr/bin/env bash
# Boots the custom kernel + initramfs under QEMU, headless, on the serial
# console. Uses -cpu max because QEMU's default CPU model (qemu64) lacks
# instruction-set extensions this project's toolchain assumed were present,
# which previously caused an illegal-instruction panic in PID 1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") --kernel PATH --initrd PATH [options]

Boot a kernel image + initramfs in QEMU, headless, on the serial console.

Required:
  --kernel PATH        Path to bzImage (or set KERNEL_IMAGE).
  --initrd PATH         Path to the initramfs .cpio.gz (or set INITRAMFS_IMAGE).

Options:
  --memory SIZE          RAM, QEMU -m syntax (or set QEMU_MEMORY). Default: 512M
  --smp N                 vCPU count (or set QEMU_SMP). Default: 1
  --append ARGS           Extra kernel command-line args, appended after the
                           defaults (console=ttyS0) (or set QEMU_APPEND).
  --graphical              Show a QEMU display window instead of -nographic.
  -h, --help               Show this help and exit.

Environment variable equivalents: KERNEL_IMAGE, INITRAMFS_IMAGE, QEMU_MEMORY,
QEMU_SMP, QEMU_APPEND.

Always uses -cpu max: this project hit a "kill init" / illegal-instruction
panic under QEMU's default qemu64 CPU model, because the locally-built
BusyBox/kernel assumed instruction-set extensions qemu64 doesn't expose.
-cpu max exposes the host's full instruction set to the guest.

Prints the exact QEMU command before running it, and does not suppress
QEMU's output or exit code.
EOF
}

KERNEL_IMAGE="$(env_default KERNEL_IMAGE "")"
INITRAMFS_IMAGE="$(env_default INITRAMFS_IMAGE "")"
MEMORY="$(env_default QEMU_MEMORY "512M")"
SMP="$(env_default QEMU_SMP "1")"
EXTRA_APPEND="$(env_default QEMU_APPEND "")"
GRAPHICAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel) KERNEL_IMAGE="$2"; shift 2 ;;
        --initrd) INITRAMFS_IMAGE="$2"; shift 2 ;;
        --memory) MEMORY="$2"; shift 2 ;;
        --smp) SMP="$2"; shift 2 ;;
        --append) EXTRA_APPEND="$2"; shift 2 ;;
        --graphical) GRAPHICAL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_fatal "Unknown argument: $1 (see --help)" ;;
    esac
done

[[ -n "${KERNEL_IMAGE}" ]] || { usage; log_fatal "Missing --kernel PATH (or set KERNEL_IMAGE)."; }
[[ -n "${INITRAMFS_IMAGE}" ]] || { usage; log_fatal "Missing --initrd PATH (or set INITRAMFS_IMAGE)."; }
require_file "${KERNEL_IMAGE}" "Kernel image (bzImage)"
require_file "${INITRAMFS_IMAGE}" "Initramfs archive"
require_cmd qemu-system-x86_64

APPEND="console=ttyS0"
[[ -n "${EXTRA_APPEND}" ]] && APPEND="${APPEND} ${EXTRA_APPEND}"

QEMU_ARGS=(
    -kernel "${KERNEL_IMAGE}"
    -initrd "${INITRAMFS_IMAGE}"
    -append "${APPEND}"
    -m "${MEMORY}"
    -smp "${SMP}"
    -cpu max
)
if ((GRAPHICAL == 0)); then
    QEMU_ARGS+=(-nographic)
fi

log_info "Command: qemu-system-x86_64 ${QEMU_ARGS[*]}"
log_info "Serial console is on this terminal. Press Ctrl-A X to quit QEMU (-nographic)."
exec qemu-system-x86_64 "${QEMU_ARGS[@]}"
