# Use BusyBox for a minimal initramfs

## Status

Accepted

## Context

Booting the custom kernel to a usable shell needs an initramfs
containing, at minimum, an `/init` and enough userspace tooling to mount
`/proc`/`/sys` and run commands. A full distribution root filesystem is
unnecessary for this project's goal (booting the kernel and confirming
it runs), and would add build time, image size, and dependencies
unrelated to the kernel work being tested.

## Decision

Use BusyBox, statically linked, as the sole userspace in the initramfs.
A single BusyBox binary plus applet symlinks provides a POSIX-ish shell
and enough coreutils (`mount`, `cat`, `echo`, ...) to drive the QEMU
boot and character-device tests, with one binary and no dynamic linker
dependency to get wrong at boot.

## Consequences

- The initramfs stays small and fast to rebuild.
- Static linking is required — a dynamically-linked BusyBox has no
  loader available this early in boot, so `scripts/build-busybox.sh`
  fails explicitly if a static build isn't achievable rather than
  producing a broken initramfs.
- BusyBox's applets are close enough to their GNU coreutils equivalents
  for this project's needs, but are not full drop-in replacements;
  scripts relying on BusyBox's `ash`/utilities should not assume GNU
  bash/coreutils behavior.
