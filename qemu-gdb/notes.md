# QEMU + GDB kernel debugging

## Boot command

    qemu-system-x86_64 \
      -kernel arch/x86/boot/bzImage \
      -initrd ../initramfs.cpio.gz \
      -append "console=ttyS0 nokaslr" \
      -nographic -m 512M \
      -cpu max \
      -s -S

`-s` opens a GDB server on port 1234; `-S` halts the CPU at startup so
GDB can attach before any instruction executes.

## GDB session

    cd ~/linux-kernel-lab/linux
    gdb vmlinux
    (gdb) target remote :1234
    (gdb) break start_kernel
    (gdb) continue
    (gdb) bt
    (gdb) continue

## Notes

- `nokaslr` is required. Without it, KASLR randomizes kernel symbol
  addresses at boot and the breakpoint on `start_kernel` won't resolve.
- `CONFIG_DEBUG_INFO` and `CONFIG_GDB_SCRIPTS` must be enabled in the
  kernel config, otherwise `vmlinux` has no symbols for GDB to read.
- Early boot attempts panicked with "Attempted to kill init" —
  `asm_exc_invalid_op` in the trace showed an illegal instruction in
  PID 1. Root cause was QEMU's default CPU model (`qemu64`) lacking
  instruction set extensions the local toolchain assumed present when
  building BusyBox. Fixed with `-cpu max`.

## Breakpoint hit output

    (gdb) target remote :1234
    Remote debugging using :1234
    0x000000000000fff0 in exception_stacks ()
    Breakpoint 1 at 0xffffffff83564be0: file init/main.c, line 904.
    (gdb) continue
    Continuing.

    Breakpoint 1, start_kernel () at init/main.c:904
    904 {

## Backtrace output

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
