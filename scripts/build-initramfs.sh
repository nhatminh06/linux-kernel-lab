#!/usr/bin/env bash
# Packages a statically-linked BusyBox install into a minimal cpio.gz
# initramfs suitable for booting the custom kernel in QEMU.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/common.sh
source "${SCRIPT_DIR}/common.sh"
REPO_ROOT="$(repo_root)"

usage() {
    cat <<EOF
Usage: $(basename "$0") --busybox-dir PATH [options]

Build a minimal initramfs (bin/sbin/etc/proc/sys/dev/tmp + a static
BusyBox + a small /init) and package it as gzip-compressed newc cpio.

Required:
  --busybox-dir PATH      Staging dir from build-busybox.sh, containing
                           bin/busybox (or set BUSYBOX_INSTALL_DIR).

Options:
  --staging-dir PATH       Directory to assemble the initramfs tree in
                            (or set INITRAMFS_STAGING_DIR). Default:
                            ${LAB_DEFAULT_WORKDIR}/initramfs-root
  --output PATH             Output archive path (or set INITRAMFS_OUTPUT).
                            Default: ${LAB_DEFAULT_WORKDIR}/initramfs.cpio.gz
  -h, --help                Show this help and exit.

Environment variable equivalents: BUSYBOX_INSTALL_DIR, INITRAMFS_STAGING_DIR,
INITRAMFS_OUTPUT.

The generated /init is a plain BusyBox ash script: it mounts proc, sysfs
and devtmpfs (devtmpfs auto-populates /dev, so no device nodes need to be
created at build time — this script never needs root), then execs an
interactive shell on the console. See the comment in the generated file,
and README.md, for the full listing.

Requires no root privileges: device nodes come from devtmpfs at boot,
not from mknod at packaging time.
EOF
}

BUSYBOX_DIR="$(env_default BUSYBOX_INSTALL_DIR "")"
STAGING_DIR="$(env_default INITRAMFS_STAGING_DIR "${LAB_DEFAULT_WORKDIR}/initramfs-root")"
OUTPUT_PATH="$(env_default INITRAMFS_OUTPUT "${LAB_DEFAULT_WORKDIR}/initramfs.cpio.gz")"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --busybox-dir) BUSYBOX_DIR="$2"; shift 2 ;;
        --staging-dir) STAGING_DIR="$2"; shift 2 ;;
        --output) OUTPUT_PATH="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) log_fatal "Unknown argument: $1 (see --help)" ;;
    esac
done

[[ -n "${BUSYBOX_DIR}" ]] || { usage; log_fatal "Missing --busybox-dir PATH (or set BUSYBOX_INSTALL_DIR); run build-busybox.sh first."; }
require_dir "${BUSYBOX_DIR}" "BusyBox install directory"
require_file "${BUSYBOX_DIR}/bin/busybox" "BusyBox binary (bin/busybox under --busybox-dir)"
require_cmd cpio gzip

BUSYBOX_DIR="$(abspath "${BUSYBOX_DIR}")"
mkdir -p "${STAGING_DIR}"
STAGING_DIR="$(abspath "${STAGING_DIR}")"

case "${STAGING_DIR}" in
    "${REPO_ROOT}"/*) log_fatal "Refusing to stage the initramfs inside this repository (${STAGING_DIR})." ;;
esac

mkdir -p "$(dirname -- "${OUTPUT_PATH}")"
OUTPUT_DIR_ABS="$(abspath "$(dirname -- "${OUTPUT_PATH}")")"
case "${OUTPUT_DIR_ABS}" in
    "${REPO_ROOT}"/*) log_fatal "Refusing to write the initramfs archive inside this repository (${OUTPUT_DIR_ABS})." ;;
esac
OUTPUT_PATH="${OUTPUT_DIR_ABS}/$(basename -- "${OUTPUT_PATH}")"

log_info "Assembling initramfs tree at ${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"/{bin,sbin,etc,proc,sys,dev,tmp,usr/bin,usr/sbin}

log_info "Copying BusyBox install (binary + applet symlinks) into staging tree."
cp -a "${BUSYBOX_DIR}/." "${STAGING_DIR}/"

cat >"${STAGING_DIR}/init" <<'INIT_EOF'
#!/bin/sh
# Minimal initramfs init (PID 1). Kept deliberately simple/readable:
#   1. Mount the three pseudo-filesystems the kernel expects userspace
#      to provide: proc, sysfs, and devtmpfs. devtmpfs auto-creates
#      device nodes (/dev/console, /dev/null, ...) so nothing needs to
#      be pre-created when this archive was packaged, and no root
#      privileges were needed to build it.
#   2. Print the kernel version so a successful boot is visible in the
#      serial console log (see docs/evidence-checklist.md).
#   3. Hand off to an interactive BusyBox ash shell on the console.
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo "[initramfs] linux-kernel-lab: mounted proc, sysfs, devtmpfs"
uname -a

exec /bin/sh
INIT_EOF
chmod 0755 "${STAGING_DIR}/init"

log_info "Packaging initramfs -> ${OUTPUT_PATH}"
( cd "${STAGING_DIR}" && find . -print0 | cpio --null -ov --format=newc ) 2>/dev/null | gzip -9 >"${OUTPUT_PATH}"

require_file "${OUTPUT_PATH}" "Packaged initramfs archive"
log_info "Initramfs ready."
echo "${OUTPUT_PATH}"
