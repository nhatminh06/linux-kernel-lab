# kernel-build

Notes and reference material for building the custom Linux kernel used
throughout this project. The actual Linux kernel source tree is **not**
part of this repository — see "Source acquisition" below.

## Tested kernel version

Linux **6.10**, x86_64.

## What's owned by this repository vs. upstream

| Owned by this repo | Upstream / generated, not tracked |
|---|---|
| `kernel-build/config-diff.patch` (documentation of config changes) | The Linux kernel source tree itself |
| `kernel-build/README.md` (this file) | `.config`, `vmlinux`, `bzImage`, `System.map` |
| `../scripts/build-kernel.sh` | `arch/`, `kernel/`, and all other upstream source directories |

Nothing in this directory is a build output — it is entirely
documentation and a reference config diff, so it's safe to commit.

## Source acquisition

Clone upstream Linux and check out the tested tag, outside this
repository (or anywhere on disk — `scripts/build-kernel.sh` takes the
path as an argument and never assumes it lives inside this repo):

    git clone --branch v6.10 --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

## Dependency overview

Building a kernel needs, at minimum: `gcc` (or `clang` for an `LLVM=1`
build), `ld`, `make`, `bc`, `bison`, `flex`, `perl`, and libssl/libelf
development headers (for module signing / BTF tooling, distro package
names vary). Run `../scripts/check-dependencies.sh` for a report of what
this checks and what's currently installed; it does not check the SSL/
elf dev headers since those come from distro packages, not standalone
binaries — install your distribution's `libssl-dev`/`openssl-devel` and
`libelf-dev`/`elfutils-libelf-devel` equivalents if a build fails on
missing `openssl/*.h` or `libelf.h` for `resolve_btfids`/module signing.

## Configuration workflow

1. Start from a working baseline config (e.g. your distro's
   `/boot/config-$(uname -r)` or `make defconfig`).
2. `make menuconfig` (or `O=<build-dir> make menuconfig` for an
   out-of-tree build — see `../scripts/build-kernel.sh --output`).
3. Compare against `config-diff.patch` (below) to reproduce the specific
   options this project changed.

### `CONFIG_HZ`: 1000 → 300

`CONFIG_HZ` sets the kernel timer tick rate (interrupts/second for the
scheduler and other periodic work). The default distro kernel used here
was built with `CONFIG_HZ_1000=y` (1000 Hz). This project's kernel was
configured with `CONFIG_HZ_300=y` / `CONFIG_HZ=300` instead — a lower,
less common tick rate, changed via `make menuconfig` under *Processor
type and features → Timer frequency* to see the effect on scheduling
granularity versus timer interrupt overhead. This is a deliberate,
documented experiment, not a default anyone should copy without a
reason.

### How to inspect/apply `config-diff.patch`

`config-diff.patch` is a `diff -u`-style comparison between the running
distro kernel's `.config` (Clang/LTO-built CachyOS 7.1.4) and this
project's from-scratch 6.10 `.config` (GCC-built). It's large (~14,800
lines) because it captures *every* option difference between two
different kernels' configs — toolchain identification strings, the
entire driver/feature set pruned via `localmodconfig`, and the `HZ`
change above all show up in the same diff.

Read it with a pager or diff viewer rather than trying to apply it
mechanically:

    less kernel-build/config-diff.patch
    grep -n 'CONFIG_HZ' kernel-build/config-diff.patch

It is **not** meant to be fed to `patch`/`git apply` against a fresh
source tree — the two sides reference different machines' absolute
paths and different starting kernels. Use it as a reference for which
options to flip by hand in `make menuconfig`, or supply your own known
`.config` to `scripts/build-kernel.sh --config`.

## Kernel build command

    ../scripts/build-kernel.sh --source /path/to/linux --config /path/to/.config

or, run manually:

    make O=<build-dir> -j"$(nproc)"        # GCC
    make O=<build-dir> -j"$(nproc)" LLVM=1  # Clang/LLD

## Location of `bzImage` and relationship to `vmlinux`

A successful build produces `vmlinux` at the top of the build directory
and `arch/x86/boot/bzImage` underneath it. `bzImage` is `vmlinux`
compressed and wrapped with a small bootloader stub; QEMU and real
bootloaders load `bzImage`, while GDB reads symbols from `vmlinux`. See
`../qemu-gdb/README.md` for the full explanation and the debugging
workflow that depends on this distinction.

## BusyBox and initramfs workflow

    ../scripts/build-busybox.sh --source /path/to/busybox
    ../scripts/build-initramfs.sh --busybox-dir <busybox install dir from above>

Produces a static BusyBox and packages it with a minimal `/init` into a
`cpio.gz` archive. See the root README's architecture diagram and
`../scripts/build-initramfs.sh --help` for what the generated `/init`
does.

## QEMU boot workflow

    ../scripts/run-qemu.sh --kernel <bzImage> --initrd <initramfs.cpio.gz>

See `../qemu-gdb/README.md` for the GDB-attached variant
(`../scripts/debug-kernel.sh`).

## Known toolchain problems (project-specific debugging observations)

These are the specific incompatibilities hit while building this 6.10
tree with a then-current toolchain. They are documented as what actually
happened in this environment — not every toolchain/kernel combination
will hit all (or any) of these:

1. **GCC 15 / C23 keyword conflict in the boot decompressor.** GCC 15
   changed its default `-std=` to a C23-flavored dialect, in which
   `bool`/`false`/`true` are reserved keywords. Linux 6.10 predates that
   compiler and defines its own `bool`-like types in
   `arch/x86/boot/compressed`, so the decompressor failed to build.
   Fixed by pinning `-std=gnu11` in
   `arch/x86/boot/compressed/Makefile` — the same fix later landed
   upstream once GCC 15 shipped broadly.
2. **`resolve_btfids` host-tool build failure.** The BTF ID resolver
   (built for the host, using the kernel's bundled `libbpf`) failed
   under the same newer-GCC/`-Werror` combination — specifically a
   discarded `const` qualifier treated as an error. Resolved by
   disabling `CONFIG_DEBUG_INFO_BTF`, which skips building
   `resolve_btfids` entirely.
3. **GPU driver build failures pruned, not fixed.** The `radeon`/`i915`
   drivers in this 6.10 tree hit incompatibilities with the newer
   compiler's handling of the `counted_by` attribute. Since this project
   only needed to boot inside QEMU (no GPU passthrough), these were
   pruned via `make localmodconfig` rather than patched — a legitimate
   scoping decision for a QEMU-only kernel, not a fix that would
   generalize to real hardware.
4. **GCC-built module against a Clang/LTO kernel.** The distribution
   kernel this project's `chardev-driver` was also tested against is
   built with Clang and LTO. Building the out-of-tree module with the
   default GCC toolchain produced flags the running kernel's module
   loader rejected (LTO-specific flags like `-mllvm`,
   `-fsplit-lto-unit` have no GCC equivalent). Rebuilding the module
   with `LLVM=1` (matching Clang/LLD to the running kernel's toolchain)
   resolved it. See `../chardev-driver/README.md`.
5. **Installed headers not matching the running kernel.**
   `/lib/modules/$(uname -r)/build` was briefly missing after a
   distro update left the running kernel older than the newly installed
   headers. Resolved by rebooting into the kernel the installed headers
   actually matched.
6. **QEMU's default CPU model (`qemu64`) lacking assumed instructions.**
   See `../qemu-gdb/README.md` § "Why `-cpu max` was needed" — this
   caused an illegal-instruction panic in PID 1 during early boot, not
   a build-time failure.
7. **`-cpu max` resolved the illegal-instruction boot failure** by
   exposing the host CPU's full instruction set to the QEMU guest.

None of these are claimed to be universal — they are what this specific
combination of GCC 15, Linux 6.10, and a CachyOS host produced. A
different distro, compiler version, or kernel release may hit none of
them, or different ones entirely.
