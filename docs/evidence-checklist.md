# Evidence checklist

A checklist for capturing real outputs/screenshots from running this
project's workflows, to back the claims in the root README. Nothing in
this file is a substitute for actually running the commands — it exists
so that when you do, you know what to save and where.

Save captured evidence (screenshots, terminal logs) under
`docs/assets/` using the naming suggested in `docs/assets/README.md`,
then link them from the root README's "Evidence" section.

## Kernel build

- [ ] Kernel source version (`git -C <linux-src> describe --tags` or the
      `VERSION`/`PATCHLEVEL` lines in the source tree's top-level `Makefile`)
- [ ] Compiler version used (`gcc --version` or `clang --version`)
- [ ] Kernel configuration command used (e.g. `make menuconfig` diffed
      against `kernel-build/config-diff.patch`, or the exact
      `scripts/build-kernel.sh` invocation)
- [ ] Successful build output (tail of the `make`/`build-kernel.sh` log
      showing `Kernel: arch/x86/boot/bzImage is ready`)
- [ ] `bzImage` path and file size (`ls -lh arch/x86/boot/bzImage`)
- [ ] `vmlinux` path and file size (`ls -lh vmlinux`)

## QEMU boot

- [ ] Full QEMU command used (or `scripts/run-qemu.sh`'s printed command)
- [ ] Screenshot or terminal capture of a successful boot to a shell prompt
- [ ] `uname -a` output from inside the booted guest
- [ ] Confirmation `/proc` and `/sys` are mounted inside the guest
      (`mount | grep -E 'proc|sysfs'`)
- [ ] Screenshot/log of the BusyBox shell prompt

## Character driver

- [ ] Build command and output (`make` or `make LLVM=1` in `chardev-driver/`)
- [ ] `insmod` command and its exit status
- [ ] `dmesg` output showing `mychardev: loaded, major=<N>`
- [ ] Device node details (`ls -l /dev/mychardev`)
- [ ] Write command used (e.g. `printf '...' | sudo tee /dev/mychardev`)
- [ ] Read command and output (`sudo cat /dev/mychardev`)
- [ ] `rmmod` command and `dmesg` output showing `mychardev: unloaded`
- [ ] Kernel taint state before/after load, if relevant
      (`cat /proc/sys/kernel/tainted`)

## GDB

- [ ] `scripts/debug-kernel.sh` command (or manual `-s -S` QEMU command) used
- [ ] GDB connection command (`target remote localhost:1234`)
- [ ] Breakpoint set/hit at `start_kernel` (`break start_kernel`, then the
      "Breakpoint 1, start_kernel () at init/main.c:NNN" output)
- [ ] Register view (`info registers`)
- [ ] Backtrace (`bt`)
- [ ] Source listing at the breakpoint (`list`)

## Environment

- [ ] Host operating system and version (`cat /etc/os-release`)
- [ ] Host kernel version (`uname -r`)
- [ ] GCC version (`gcc --version`)
- [ ] Clang version (`clang --version`)
- [ ] QEMU version (`qemu-system-x86_64 --version`)
- [ ] GDB version (`gdb --version`)
- [ ] BusyBox version (`busybox | head -1`)
