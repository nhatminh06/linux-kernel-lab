# Thin wrapper around scripts/*.sh. All real logic lives in the scripts;
# targets here just forward arguments so both entry points stay in sync.
#
# Environment variables (all optional, all documented per-script with
# `scripts/<name>.sh --help`):
#   LINUX_SRC, KERNEL_BUILD_DIR   - kernel source / out-of-tree build dir
#   BUSYBOX_SRC, BUSYBOX_INSTALL_DIR - BusyBox source / staging install dir
#   INITRAMFS_STAGING_DIR, INITRAMFS_OUTPUT - initramfs assembly / archive
#   KERNEL_IMAGE, INITRAMFS_IMAGE, VMLINUX_IMAGE - artifacts for run/debug
#   CHARDEV_MODULE, CHARDEV_DEVICE, CHARDEV_MESSAGE - driver smoke test
#
# Example:
#   make kernel LINUX_SRC=$HOME/src/linux KERNEL_BUILD_DIR=$HOME/kbuild

SHELL := /usr/bin/env bash
SCRIPTS := scripts

.PHONY: help check kernel busybox initramfs run debug driver test-driver clean-generated

help:
	@echo "linux-kernel-lab targets:"
	@echo "  check           Check build/debug dependencies"
	@echo "  kernel          Build the kernel (needs LINUX_SRC)"
	@echo "  busybox         Build static BusyBox (needs BUSYBOX_SRC)"
	@echo "  initramfs       Package the initramfs (needs BUSYBOX_INSTALL_DIR)"
	@echo "  run             Boot kernel+initramfs in QEMU (needs KERNEL_IMAGE, INITRAMFS_IMAGE)"
	@echo "  debug           Boot paused with a GDB stub (needs VMLINUX_IMAGE, KERNEL_IMAGE, INITRAMFS_IMAGE)"
	@echo "  driver          Build chardev-driver/chardev.ko"
	@echo "  test-driver     Smoke-test the driver (needs sudo; needs CHARDEV_MODULE or driver built)"
	@echo "  clean-generated Remove this repo's own generated build dir (./.lab-build), never source trees"
	@echo
	@echo "Run 'scripts/<name>.sh --help' for a script's full option list."
	@echo "See environment variables documented at the top of this Makefile."

check:
	@$(SCRIPTS)/check-dependencies.sh

kernel:
	@$(SCRIPTS)/build-kernel.sh

busybox:
	@$(SCRIPTS)/build-busybox.sh

initramfs:
	@$(SCRIPTS)/build-initramfs.sh

run:
	@$(SCRIPTS)/run-qemu.sh

debug:
	@$(SCRIPTS)/debug-kernel.sh

driver:
	$(MAKE) -C chardev-driver

test-driver:
	@$(SCRIPTS)/test-chardev.sh

# Only ever removes this repository's own generated output directory
# (scripts/common.sh's LAB_WORKDIR default, ./.lab-build) and the driver's
# build artifacts. Never touches LINUX_SRC/BUSYBOX_SRC or anything outside
# this repo.
clean-generated:
	@if [ -d ./.lab-build ]; then \
		echo "Removing ./.lab-build"; \
		rm -rf ./.lab-build; \
	else \
		echo "Nothing to remove: ./.lab-build does not exist"; \
	fi
	@$(MAKE) -C chardev-driver clean
