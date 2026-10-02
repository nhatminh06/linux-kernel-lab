# Technical notes

This document preserves the deeper troubleshooting record and lessons learned
without making the project landing page carry the full narrative.

## Build and runtime problems

| Problem | Root cause | Resolution |
|---|---|---|
| Boot decompressor failed under GCC 15 | Linux 6.10 predates GCC 15's C23-flavored default; the kernel's pre-C23 `bool`, `false`, and `true` definitions then conflicted with reserved keywords | Pin `-std=gnu11` in `arch/x86/boot/compressed/Makefile`; an equivalent fix later landed upstream |
| `resolve_btfids` host tool failed | The bundled `libbpf` triggered a discarded-`const` warning promoted to an error by the newer host compiler | Disable `CONFIG_DEBUG_INFO_BTF` for this scoped build |
| `radeon` and `i915` failed to compile | Linux 6.10 GPU code and the newer compiler disagreed about `counted_by` handling | Prune unused GPU drivers with `localmodconfig` for the QEMU-only target |
| Out-of-tree module would not build for the distribution kernel | The target kernel used Clang/LTO while the initial module build used GCC | Rebuild the module with `LLVM=1` to match the target kernel toolchain |
| `/lib/modules/$(uname -r)/build` was missing | Installed headers belonged to a newer kernel than the one still running | Reboot into the kernel matching the installed headers |
| PID 1 hit an illegal instruction in QEMU | The conservative `qemu64` model omitted instructions assumed by locally built code | Run this lab with `-cpu max` |

These are observations from Linux 6.10 with the documented host toolchains, not
universal remedies. In particular, `-cpu max` favors faithful local reproduction
over migration compatibility and is not a portable deployment recommendation.

## Lessons retained

- Toolchain drift can look like a kernel source defect. Kernel version,
  compiler, C dialect, module build, and target kernel must be considered as a
  single compatibility set.
- Early-boot symptoms can be far removed from their cause. Here an instruction
  set mismatch surfaced as "Attempted to kill init" rather than a CPU-feature
  diagnostic.
- `bzImage` and `vmlinux` are complementary artifacts: the former boots; the
  latter supplies symbols and, when configured, DWARF source information.
- KASLR must be disabled for this simple static-symbol GDB workflow so runtime
  addresses match `vmlinux`.
- Loading an unsigned out-of-tree module taints the kernel. That is expected in
  a local lab and should still be recorded when interpreting bug reports.

## Boundaries

- The 16-slot driver queue is global, non-blocking, and mutex-protected. Its
  partial-read cursor is shared across readers; it offers neither per-file
  cursors nor message fan-out.
- Empty reads return EOF and full writes return `ENOSPC`. There is no
  `poll`/`select`, wait queue, `ioctl`, `mmap`, persistence, DMA, or interrupt
  handling.
- The scripts report missing dependencies but never install them.
- Full kernel builds require substantial time and disk space and are outside the
  intentionally lightweight hosted CI checks.
