#!/usr/bin/env bash
# Boots the kernel under QEMU paused with a GDB stub (-s -S), and either
# prints the GDB command to run in another terminal, or launches GDB
# automatically with --auto-gdb. Mirrors the manual workflow recorded in
# qemu-gdb/notes.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/common.sh
source "${SCRIPT_DIR}/common.sh"

GDB_PORT="1234"
GDB_CMDFILE=""
QEMU_PID=""

cleanup() {
    if [[ -n "${QEMU_PID}" ]] && kill -0 "${QEMU_PID}" 2>/dev/null; then
        log_info "Stopping QEMU (pid ${QEMU_PID})."
        kill "${QEMU_PID}" 2>/dev/null || true
        wait "${QEMU_PID}" 2>/dev/null || true
    fi
    [[ -n "${GDB_CMDFILE}" && -f "${GDB_CMDFILE}" ]] && rm -f "${GDB_CMDFILE}"
    return 0
}
trap cleanup EXIT INT TERM

usage() {
    cat <<EOF
Usage: $(basename "$0") --vmlinux PATH --kernel PATH --initrd PATH [options]

Start QEMU paused (-S) with a GDB remote stub (-s, port ${GDB_PORT}) so GDB
can attach before the first instruction of the kernel runs, then either
print the GDB command to use in another terminal, or launch GDB for you.

Required:
  --vmlinux PATH      Uncompressed kernel image with debug symbols
                       (or set VMLINUX_IMAGE). This is what GDB reads
                       symbols from; it is NOT what QEMU boots.
  --kernel PATH        Bootable bzImage (or set KERNEL_IMAGE). This is
                       what QEMU boots; it has no usable debug symbols.
  --initrd PATH        Initramfs archive (or set INITRAMFS_IMAGE).

Options:
  --auto-gdb              Launch GDB automatically once QEMU is listening,
                           instead of printing the command for a second
                           terminal. QEMU is stopped when GDB exits.
  --gdb-bin NAME           GDB binary to use (or set GDB_BIN). Default: gdb.
                           A distro's default 'gdb' is not guaranteed to
                           support every target architecture; if it can't
                           debug x86-64, install/use 'gdb-multiarch' (Debian/
                           Ubuntu) or your distro's cross-gdb package and
                           pass it here.
  --break SYMBOL           Breakpoint symbol (or set GDB_BREAK). Default:
                           start_kernel.
  --memory SIZE            Passed to QEMU -m. Default: 512M.
  --append ARGS            Extra kernel command-line args appended after
                           "console=ttyS0 nokaslr".
  -h, --help                Show this help and exit.

Environment variable equivalents: VMLINUX_IMAGE, KERNEL_IMAGE,
INITRAMFS_IMAGE, GDB_BIN, GDB_BREAK.

Why "nokaslr": KASLR randomizes kernel symbol addresses at boot, so a
breakpoint on a symbol from vmlinux (a fixed address) would not match
where the code actually loaded. This script always adds "nokaslr" for a
debug boot; do not use this kernel command line for anything else.

Debug symbols matter: without CONFIG_DEBUG_INFO (and CONFIG_GDB_SCRIPTS)
enabled in the kernel .config that produced --vmlinux, GDB has addresses
but no source/line information, and 'break start_kernel' has nothing to
resolve against.

This script never leaves a background QEMU process running: it is killed
on exit whether GDB exits normally, this script is interrupted, or an
error occurs (see the EXIT/INT/TERM trap above).
EOF
}

VMLINUX="$(env_default VMLINUX_IMAGE "")"
KERNEL_IMAGE="$(env_default KERNEL_IMAGE "")"
INITRAMFS_IMAGE="$(env_default INITRAMFS_IMAGE "")"
GDB_BIN="$(env_default GDB_BIN "gdb")"
BREAK_SYMBOL="$(env_default GDB_BREAK "start_kernel")"
MEMORY="512M"
EXTRA_APPEND=""
AUTO_GDB=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vmlinux) VMLINUX="$2"; shift 2 ;;
        --kernel) KERNEL_IMAGE="$2"; shift 2 ;;
        --initrd) INITRAMFS_IMAGE="$2"; shift 2 ;;
        --auto-gdb) AUTO_GDB=1; shift ;;
        --gdb-bin) GDB_BIN="$2"; shift 2 ;;
        --break) BREAK_SYMBOL="$2"; shift 2 ;;
        --memory) MEMORY="$2"; shift 2 ;;
        --append) EXTRA_APPEND="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) log_fatal "Unknown argument: $1 (see --help)" ;;
    esac
done

[[ -n "${VMLINUX}" ]] || { usage; log_fatal "Missing --vmlinux PATH (or set VMLINUX_IMAGE)."; }
[[ -n "${KERNEL_IMAGE}" ]] || { usage; log_fatal "Missing --kernel PATH (or set KERNEL_IMAGE)."; }
[[ -n "${INITRAMFS_IMAGE}" ]] || { usage; log_fatal "Missing --initrd PATH (or set INITRAMFS_IMAGE)."; }
require_file "${VMLINUX}" "vmlinux (debug symbols)"
require_file "${KERNEL_IMAGE}" "Kernel image (bzImage)"
require_file "${INITRAMFS_IMAGE}" "Initramfs archive"
require_cmd qemu-system-x86_64

if ! command -v "${GDB_BIN}" >/dev/null 2>&1; then
    log_fatal "GDB binary '${GDB_BIN}' not found. Install gdb, or pass --gdb-bin/GDB_BIN if your target isn't natively supported by the default gdb package."
fi

APPEND="console=ttyS0 nokaslr"
[[ -n "${EXTRA_APPEND}" ]] && APPEND="${APPEND} ${EXTRA_APPEND}"

GDB_CMDFILE="$(mktemp)"
cat >"${GDB_CMDFILE}" <<EOF
target remote localhost:${GDB_PORT}
break ${BREAK_SYMBOL}
continue
EOF

log_info "Starting QEMU paused, GDB stub on localhost:${GDB_PORT} (-s -S)."
QEMU_ARGS=(
    -kernel "${KERNEL_IMAGE}"
    -initrd "${INITRAMFS_IMAGE}"
    -append "${APPEND}"
    -m "${MEMORY}"
    -cpu max
    -nographic
    -s -S
)
log_info "Command: qemu-system-x86_64 ${QEMU_ARGS[*]}"

qemu-system-x86_64 "${QEMU_ARGS[@]}" &
QEMU_PID=$!
sleep 1
if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
    log_fatal "QEMU exited immediately; see output above."
fi

if ((AUTO_GDB)); then
    log_info "Launching ${GDB_BIN} ${VMLINUX} with breakpoint at ${BREAK_SYMBOL}."
    "${GDB_BIN}" -q -x "${GDB_CMDFILE}" "${VMLINUX}" || true
else
    cat <<EOF

QEMU is running (pid ${QEMU_PID}), paused, GDB stub on localhost:${GDB_PORT}.
In another terminal, run:

    ${GDB_BIN} ${VMLINUX}
    (gdb) target remote localhost:${GDB_PORT}
    (gdb) break ${BREAK_SYMBOL}
    (gdb) continue

Or non-interactively:

    ${GDB_BIN} -x ${GDB_CMDFILE} ${VMLINUX}

Press Ctrl-C here to stop QEMU when you are done.
EOF
    wait "${QEMU_PID}"
fi
