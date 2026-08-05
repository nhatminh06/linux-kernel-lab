# QEMU + GDB kernel debugging

How this project boots the custom kernel under QEMU with a live GDB
connection, halts before the first instruction of `start_kernel()`, and
inspects early boot state. The transcript at the bottom of this file is
a real session captured while working through this lab.

Use `../scripts/debug-kernel.sh` to reproduce this workflow instead of
typing the commands below by hand — this document explains what that
script automates and why.

## bzImage vs. vmlinux

The kernel build produces two artifacts from the same compile:

| File | What it is | Used by |
|---|---|---|
| `vmlinux` | Uncompressed ELF kernel image with symbol table and (if enabled) DWARF debug info | GDB |
| `arch/x86/boot/bzImage` | `vmlinux` wrapped in a self-extracting bootloader-compatible container, gzip-compressed | QEMU / a real bootloader |

QEMU's `-kernel` flag needs `bzImage` because it needs something a real
boot process can jump to and decompress — `vmlinux` is not a bootable
image on its own. GDB needs `vmlinux` because that's the file that still
has symbol names and (with the right config) source-line information;
`bzImage`'s compressed payload isn't something GDB can read symbols from.

## `-s` and `-S`

    qemu-system-x86_64 -kernel bzImage -initrd initramfs.cpio.gz \
      -append "console=ttyS0 nokaslr" -nographic -m 512M -cpu max \
      -s -S

- **`-s`** is shorthand for `-gdb tcp::1234` — it starts a GDB remote
  stub inside QEMU listening on TCP port 1234.
- **`-S`** freezes the virtual CPU at startup instead of letting it run.
  Without `-S`, the kernel would already be executing (possibly past
  `start_kernel`) by the time GDB attaches, and the breakpoint below
  could be set too late to catch it.

The system starts paused so that GDB can attach, set breakpoints, and
`continue` execution from address zero — otherwise there's a race
between QEMU booting and GDB connecting.

## Connecting GDB and breaking at `start_kernel`

    cd <path-to-linux-source>          # or wherever your vmlinux is
    gdb vmlinux
    (gdb) target remote localhost:1234
    (gdb) break start_kernel
    (gdb) continue

`scripts/debug-kernel.sh` does the same thing, either printing this
sequence for you to run in a second terminal, or (with `--auto-gdb`)
launching GDB itself and generating a temporary GDB command file with
these exact commands.

## Inspecting state once stopped

    (gdb) info registers      # register file at the breakpoint
    (gdb) bt                  # backtrace / call stack
    (gdb) list                # source lines around the current PC
    (gdb) step / next         # single-step through early init
    (gdb) print some_variable # inspect a variable (needs debug info)

## Why debug symbols matter

`vmlinux` always has a symbol table, but `break start_kernel` resolving
to a specific *line* (`init/main.c:904` in the transcript below) and
`list`/`bt` showing source locations both require the kernel to have
been built with:

- `CONFIG_DEBUG_INFO=y` (DWARF debug info emitted into `vmlinux`)
- `CONFIG_GDB_SCRIPTS=y` (ships the kernel's own GDB helper Python
  scripts, useful for kernel-aware commands like `lx-dmesg`, though not
  required for a plain breakpoint-and-backtrace session like this one)

Without `CONFIG_DEBUG_INFO`, GDB can still set a breakpoint on an
exported symbol's address, but `bt`/`list` will show `??` instead of
source lines.

## Why KASLR interferes, and how to disable it here

KASLR (`CONFIG_RANDOMIZE_BASE`) randomizes where the kernel is loaded in
memory at boot. `vmlinux`'s symbol table encodes addresses from the
*link-time* layout; if the running kernel relocated itself, `break
start_kernel` (resolved against `vmlinux`'s static addresses) will not
match where the code actually is, and the breakpoint silently never
fires. Appending `nokaslr` to the kernel command line disables the
relocation for this debug boot, so the addresses GDB computes from
`vmlinux` match what's actually running.

`nokaslr` is a debugging aid, not something to carry into a "real" boot
of this kernel — `scripts/run-qemu.sh` (day-to-day boot) does not add
it; `scripts/debug-kernel.sh` (GDB workflow) always does.

## Why `-cpu max` was needed

Early attempts to boot under QEMU's default CPU model (`qemu64`) panicked
with "Attempted to kill init" during boot. The backtrace pointed at
`asm_exc_invalid_op` — an illegal-instruction exception in PID 1, not
anywhere that named the actual cause. `qemu64` is a deliberately
conservative baseline CPU model and doesn't expose every instruction-set
extension a locally-built toolchain may assume is present (e.g. from
`-march=native`-flavored BusyBox/kernel builds). `-cpu max` tells QEMU to
expose the host CPU's full feature set to the guest, which resolved it.
Both `scripts/run-qemu.sh` and `scripts/debug-kernel.sh` always pass
`-cpu max` for this reason.

## Common failure cases

| Symptom | Likely cause |
|---|---|
| `break start_kernel` never triggers | KASLR is active — add `nokaslr` |
| `bt`/`list` show `??`/no source | Kernel wasn't built with `CONFIG_DEBUG_INFO=y` |
| "Attempted to kill init", `asm_exc_invalid_op` in the trace | QEMU CPU model missing instructions the guest assumes — add `-cpu max` |
| GDB connects but target arch mismatch / garbled registers | System `gdb` doesn't support the target architecture — try `gdb-multiarch` |
| `target remote localhost:1234` refused | QEMU wasn't started with `-s`, or a previous QEMU instance is still holding the port |

## Boot command (reference)

    qemu-system-x86_64 \
      -kernel arch/x86/boot/bzImage \
      -initrd ../initramfs.cpio.gz \
      -append "console=ttyS0 nokaslr" \
      -nographic -m 512M \
      -cpu max \
      -s -S

## GDB session (reference)

    cd ~/linux-kernel-lab/linux
    gdb vmlinux
    (gdb) target remote :1234
    (gdb) break start_kernel
    (gdb) continue
    (gdb) bt
    (gdb) continue

## Recorded transcript

Captured output from a real session (paths reflect the original working
machine, not this repository's layout):

    (gdb) target remote :1234
    Remote debugging using :1234
    0x000000000000fff0 in exception_stacks ()
    Breakpoint 1 at 0xffffffff83564be0: file init/main.c, line 904.
    (gdb) continue
    Continuing.

    Breakpoint 1, start_kernel () at init/main.c:904
    904 {

    (gdb) bt
    #0  start_kernel () at init/main.c:904
    #1  0xffffffff83574134 in x86_64_start_reservations (
        real_mode_data=real_mode_data@entry=0x13c90 <exception_stacks+31888> <error: Cannot access memory at address 0x13c90>)
        at arch/x86/kernel/head64.c:507
    #2  0xffffffff8357422e in x86_64_start_kernel (
        real_mode_data=0x13c90 <exception_stacks+31888> <error: Cannot access memory at address 0x13c90>)
        at arch/x86/kernel/head64.c:488
    #3  0xffffffff81035c26 in secondary_startup_64 ()
        at arch/x86/kernel/head_64.S:420
    #4  0x0000000000000000 in ?? ()

The `<error: Cannot access memory at address ...>` lines are GDB failing
to dereference a pointer argument that lives in memory not yet mapped
this early in boot — expected at this point in initialization, not a
sign of a broken session.
