#!/usr/bin/env bash
# Functional test for the chardev-driver message ring.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") --module PATH [options]

Test the mychardev message ring, including FIFO ordering, binary data,
partial reads, capacity handling, and reuse after draining.

Required:
  --module PATH         Path to the built chardev.ko (or set CHARDEV_MODULE).

Options:
  --device PATH          Device node path (or set CHARDEV_DEVICE).
                          Default: /dev/mychardev
  --message STRING        Test message (or set CHARDEV_MESSAGE). Default:
                          "hello from test-chardev.sh". Must fit in the
                          driver's 256-byte payload limit.
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

if [[ "${EUID}" -ne 0 ]]; then
    log_fatal "This test loads a kernel module and writes to a device node; re-run with sudo."
fi

require_cmd dmesg insmod rmmod lsmod python3

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

log_info "Running message-ring tests against ${DEVICE_PATH}."
python3 - "${DEVICE_PATH}" "${MESSAGE}" <<'PY'
import errno
import os
import sys

device, configured_message = sys.argv[1:]


def write_message(payload):
    fd = os.open(device, os.O_WRONLY)
    try:
        written = os.write(fd, payload)
    finally:
        os.close(fd)
    assert written == len(payload), (written, len(payload))


def read_message(size=256):
    fd = os.open(device, os.O_RDONLY)
    try:
        return os.read(fd, size)
    finally:
        os.close(fd)


# Drain messages left by a module that was already loaded before this test.
while read_message():
    pass

payload = configured_message.encode()
if len(payload) > 256:
    raise ValueError(
        f"configured test message is {len(payload)} bytes; maximum is 256"
    )
write_message(payload)
assert read_message() == payload

fifo = [b"first", b"second", b"third"]
for payload in fifo:
    write_message(payload)
for payload in fifo:
    assert read_message() == payload

binary = b"before\x00after"
write_message(binary)
assert read_message(4) == binary[:4]
assert read_message() == binary[4:]

for number in range(16):
    write_message(bytes([number]))
try:
    write_message(b"overflow")
except OSError as error:
    assert error.errno == errno.ENOSPC, error
else:
    raise AssertionError("17th queued message unexpectedly succeeded")

for number in range(16):
    assert read_message() == bytes([number])

write_message(b"reused")
assert read_message() == b"reused"
assert read_message() == b""
PY

log_info "Recent dmesg output after write/read:"
dmesg | tail -10

if ((LOADED_BY_SCRIPT)); then
    log_info "Unloading module ${MODULE_NAME} to verify clean removal."
    rmmod "${MODULE_NAME}"
    LOADED_BY_SCRIPT=0
    if lsmod | grep -qw "${MODULE_NAME}"; then
        log_fatal "Module ${MODULE_NAME} is still loaded after rmmod."
    fi
fi

log_info "PASS: message-ring tests completed successfully."
