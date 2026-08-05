#!/usr/bin/env bash
# Smoke test for chardev-driver: loads the module (if not already loaded),
# writes a message to /dev/mychardev, reads it back, and checks the two
# match exactly. Matches the driver's actual semantics: a write replaces a
# single shared message buffer, and read returns exactly what was last
# written (see chardev-driver/chardev.c).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"
REPO_ROOT="$(repo_root)"

usage() {
    cat <<EOF
Usage: $(basename "$0") --module PATH [options]

Smoke-test the mychardev character device: load the module if needed,
write a message, read it back, and compare byte-for-byte.

Required:
  --module PATH         Path to the built chardev.ko (or set CHARDEV_MODULE).

Options:
  --device PATH          Device node path (or set CHARDEV_DEVICE).
                          Default: /dev/mychardev
  --message STRING        Test message (or set CHARDEV_MESSAGE). Default:
                          "hello from test-chardev.sh". Must fit in the
                          driver's 256-byte buffer (255 usable bytes).
  --allow-mknod            If the device node doesn't appear automatically
                            (e.g. no udev running), create it manually with
                            mknod using the major number from dmesg. Off by
                            default — this is a system-modifying fallback.
  -h, --help                Show this help and exit.

Environment variable equivalents: CHARDEV_MODULE, CHARDEV_DEVICE,
CHARDEV_MESSAGE.

Requires root (loading a kernel module and writing to a device node under
/dev both require it). The script only unloads the module if it loaded it
itself; a module that was already loaded before this script ran is left
alone, and no other modules or device nodes are ever touched.
EOF
}

MODULE_PATH="$(env_default CHARDEV_MODULE "")"
DEVICE_PATH="$(env_default CHARDEV_DEVICE "/dev/mychardev")"
MESSAGE="$(env_default CHARDEV_MESSAGE "hello from test-chardev.sh")"
ALLOW_MKNOD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --module) MODULE_PATH="$2"; shift 2 ;;
        --device) DEVICE_PATH="$2"; shift 2 ;;
        --message) MESSAGE="$2"; shift 2 ;;
        --allow-mknod) ALLOW_MKNOD=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_fatal "Unknown argument: $1 (see --help)" ;;
    esac
done

[[ -n "${MODULE_PATH}" ]] || { usage; log_fatal "Missing --module PATH (or set CHARDEV_MODULE); build it first with 'make' in chardev-driver/."; }
require_file "${MODULE_PATH}" "chardev kernel module"

if ((${#MESSAGE} > 255)); then
    log_fatal "Test message is ${#MESSAGE} bytes; the driver's buffer only holds 255 usable bytes."
fi

if [[ "${EUID}" -ne 0 ]]; then
    log_fatal "This test loads a kernel module and writes to a device node; re-run with sudo."
fi

require_cmd dmesg insmod rmmod lsmod

LOADED_BY_SCRIPT=0
MKNOD_BY_SCRIPT=0

cleanup() {
    if ((MKNOD_BY_SCRIPT)) && [[ -e "${DEVICE_PATH}" ]]; then
        log_info "Removing manually-created device node ${DEVICE_PATH}."
        rm -f "${DEVICE_PATH}"
    fi
    if ((LOADED_BY_SCRIPT)); then
        log_info "Unloading module ${MODULE_NAME} (loaded by this script)."
        rmmod "${MODULE_NAME}" 2>/dev/null || log_warn "rmmod ${MODULE_NAME} failed; it may already be gone."
    fi
    return 0
}
trap cleanup EXIT

MODULE_NAME="$(basename "${MODULE_PATH}" .ko)"
if lsmod | grep -qw "${MODULE_NAME}"; then
    log_info "Module ${MODULE_NAME} already loaded; leaving it as-is (will not be removed by this script)."
else
    log_info "Loading module: insmod ${MODULE_PATH}"
    insmod "${MODULE_PATH}"
    LOADED_BY_SCRIPT=1
fi

log_info "Recent dmesg output for mychardev:"
dmesg | grep -i mychardev | tail -5 || true

log_info "Waiting for ${DEVICE_PATH} to appear (udev auto-creates it via device_create() in the driver)."
for _ in $(seq 1 20); do
    [[ -e "${DEVICE_PATH}" ]] && break
    sleep 0.1
done

if [[ ! -e "${DEVICE_PATH}" ]]; then
    MAJOR="$(dmesg | grep -i 'mychardev: loaded, major=' | tail -1 | grep -oE 'major=[0-9]+' | cut -d= -f2 || true)"
    if ((ALLOW_MKNOD)) && [[ -n "${MAJOR}" ]]; then
        log_warn "Device node did not appear automatically (no udev?); creating it manually with mknod."
        mknod "${DEVICE_PATH}" c "${MAJOR}" 0
        chmod 666 "${DEVICE_PATH}"
        MKNOD_BY_SCRIPT=1
    else
        log_fatal "${DEVICE_PATH} was not created automatically. This driver relies on udev (via class_create()/device_create()) to create the node; if this system has no udev running, re-run with --allow-mknod, or manually: mknod ${DEVICE_PATH} c <major-from-dmesg> 0"
    fi
fi

log_info "Writing test message to ${DEVICE_PATH}: ${MESSAGE@Q}"
printf '%s' "${MESSAGE}" >"${DEVICE_PATH}"

ACTUAL="$(cat "${DEVICE_PATH}")"

log_info "Recent dmesg output after write/read:"
dmesg | tail -10

if [[ "${ACTUAL}" == "${MESSAGE}" ]]; then
    log_info "PASS: read back exactly what was written (${#ACTUAL} bytes)."
    exit 0
else
    log_warn "Expected: ${MESSAGE@Q}"
    log_warn "Actual:   ${ACTUAL@Q}"
    log_fatal "FAIL: device did not return the same bytes that were written."
fi
