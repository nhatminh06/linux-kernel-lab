# Linux Kernel Lab

Hands-on notes from a Linux kernel and driver project completed on CachyOS.

## Custom kernel build

Built Linux v6.10 from source via `make menuconfig`, lowering `CONFIG_HZ`
from 1000 to 300. Two toolchain compatibility issues surfaced during the
build:

- A GCC 15 / C23 keyword conflict in the boot decompressor, resolved by
  backporting `-std=gnu11` to `arch/x86/boot/compressed/Makefile` (the
  same fix later merged upstream).
- A broken BTF host-tool build (`libbpf` / GCC incompatibility in
  `resolve_btfids`), resolved by disabling `CONFIG_DEBUG_INFO_BTF`.

Booted the resulting `bzImage` in QEMU with a custom BusyBox initramfs.

See: `kernel-build/config-diff.patch`

## Character device driver

A minimal character driver (`chardev-driver/chardev.c`) implementing
`read` and `write` through the chardev API, exposing `/dev/mychardev`.
Built against a Clang/LLVM-built kernel using `LLVM=1`, and tested by
writing a string to the device and reading it back.

    make
    sudo insmod chardev.ko
    sudo dmesg | tail            # mychardev: loaded, major=<N>
    echo "hello kernel" | sudo tee /dev/mychardev
    sudo cat /dev/mychardev      # hello kernel
    sudo rmmod chardev

## QEMU + GDB kernel debugging

Booted the custom kernel under QEMU with `-s -S`, attached GDB to the
remote stub, set a breakpoint at `start_kernel`, and walked the early
boot call stack.

See: `qemu-gdb/notes.md`

## Bugs encountered

| Problem | Root cause | Fix |
|---|---|---|
| Boot decompressor build failure | GCC 15 defaults to C23, where `bool`/`false` are reserved keywords, conflicting with the kernel's own definitions | Backported `-std=gnu11` to `arch/x86/boot/compressed/Makefile` |
| `resolve_btfids` host-tool build failure | Same GCC/`libbpf` incompatibility (`-Werror` on a discarded `const` qualifier) | Disabled `CONFIG_DEBUG_INFO_BTF` |
| `radeon`/`i915` driver build failures | v6.10 code incompatible with newer GCC's `counted_by` attribute handling | Pruned unused GPU drivers via `make localmodconfig` |
| Module wouldn't build | CachyOS kernel is built with Clang/LTO; module build defaulted to GCC and hit unrecognized flags (`-mllvm`, `-fsplit-lto-unit`) | Rebuilt with `LLVM=1` |
| `/lib/modules/$(uname -r)/build` missing | Running kernel was older than installed headers after a `pacman` update | Rebooted into the matching kernel |
| `init` panic on QEMU boot | Default QEMU CPU model lacked instruction set extensions the local toolchain assumed | Added `-cpu max` |

## What I learned

- Toolchain version drift breaks things in ways that look like kernel
  bugs but aren't. GCC 15 changing its default C standard to C23 broke
  a kernel released before that compiler existed, in three separate
  places.
- The kernel build system, the out-of-tree module build system, and the
  userspace toolchain all have to agree on compiler and C standard.
  A Clang/LTO-built distro kernel can't have GCC-built modules loaded
  against it.
- QEMU's default CPU model is deliberately conservative and will silently
  mismatch binaries compiled for the host's actual microarchitecture —
  the failure surfaces as an illegal-instruction panic in PID 1, not as
  anything that names the real cause.
- Loading an unsigned module taints the kernel (visible in
  `/proc/sys/kernel/tainted`), which is expected for local development
  but worth understanding before it shows up in a bug report.