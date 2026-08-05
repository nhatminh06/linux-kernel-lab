# Build the out-of-tree module with a toolchain matching the target kernel

## Status

Accepted

## Context

`chardev-driver` was also built and loaded against a distribution kernel
(CachyOS) that ships built with Clang and LTO
(`CONFIG_LTO_CLANG_THIN=y`-style). Building the module with the default
GCC toolchain produced Clang/LTO-specific compiler flags
(`-mllvm`, `-fsplit-lto-unit`) that GCC does not understand, so the
build failed outright rather than producing a module that merely failed
to load.

## Decision

Build out-of-tree modules with the same toolchain family the target
kernel was built with. In practice: `make LLVM=1` when targeting a
Clang/LTO kernel, plain `make` (GCC) when targeting a GCC-built kernel
such as this project's own Linux 6.10 build. `scripts/test-chardev.sh`
and `chardev-driver/README.md` document `LLVM=1` as an explicit,
opt-in flag rather than a default, since this project's own kernel was
built with GCC and only the separately-tested distro-kernel path needed
Clang.

## Consequences

- Module builds now match the target kernel's `CONFIG_CC_IS_GCC` /
  `CONFIG_CC_IS_CLANG` and LTO settings, avoiding the flag-mismatch
  build failure.
- Anyone reproducing this project against a different running kernel
  must first check `/proc/config.gz` (or `zcat /proc/config.gz | grep
  CONFIG_CC_IS`) or equivalent to know which toolchain to pass, rather
  than assuming GCC.
- This is a general Linux kernel module constraint, not specific to this
  driver — it applies to any out-of-tree module built against a
  Clang/LTO kernel.
