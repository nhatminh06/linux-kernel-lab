# chardev-driver

A minimal Linux character-device driver used to demonstrate userspace ↔
kernel communication through the standard `read`/`write` VFS interface.

## What it does

`chardev.c` registers a character device named `mychardev` backed by a
single 256-byte in-kernel buffer (`msg`):

- **write(2)** copies up to 255 bytes from the calling process into `msg`
  via `copy_from_user()`, null-terminates it, and records the length.
- **read(2)** returns exactly the bytes from the most recent write, via
  `simple_read_from_buffer()` (a kernel helper that safely copies to
  userspace and advances the file offset for you).
- A single `struct mutex` (`dev_lock`) serializes access to `msg`, since
  the buffer is shared by every open file descriptor — without it,
  concurrent writers/readers from different processes could interleave.

There is deliberately no ioctl, no per-open state, and no growth beyond
one buffer: this is a teaching driver for the VFS `file_operations`
interface, not a general-purpose IPC mechanism.

## How the major number is assigned

`register_chrdev(0, DEVICE_NAME, &fops)` passes major `0`, which asks the
kernel to allocate a **free major number dynamically** rather than
hard-coding one (hard-coded majors risk colliding with another driver).
The allocated major is printed to the kernel log on load:

    mychardev: loaded, major=<N>

Because the major is dynamic, it can differ between boots/loads — always
read it from `dmesg`, never assume a fixed value.

## How `/dev/mychardev` is created

The driver creates its own device node via the `class_create()` /
`device_create()` kernel APIs in `chardev_init()`. On any system running
`udev` (or `mdev`/`eudev`), this triggers automatic creation of
`/dev/mychardev` with no manual `mknod` step required. If a system has no
device-node manager running (e.g. a very stripped-down initramfs),
`scripts/test-chardev.sh --allow-mknod` falls back to creating the node
manually using the major number parsed from `dmesg`.

**Kernel version note:** `class_create()` takes a single argument (just
the class name) as of Linux 6.4, which changed from the older two-argument
`class_create(THIS_MODULE, name)` signature. This driver uses the newer,
single-argument form and therefore targets **Linux ≥ 6.4** — see
"Tested kernel and compiler information" below.

## Build instructions

Build against your currently-running kernel's headers (`/lib/modules/$(uname
-r)/build`), from this directory:

    make               # builds with the default toolchain (gcc)
    make LLVM=1        # builds with Clang/LLD instead

Use `LLVM=1` when your running kernel was itself built with Clang/LTO —
mixing a GCC-built module with a Clang/LTO kernel produces incompatible
flags and the module will fail to build or load (see the root README's
"Technical challenges" table). This repository's own kernel was built
with GCC; `LLVM=1` was required separately when building this module
against a distribution kernel that used Clang/LTO.

`scripts/test-chardev.sh` in the repository root automates load, write,
read-back, and unload as a smoke test.

## Load and unload

    sudo insmod chardev.ko
    sudo dmesg | tail            # mychardev: loaded, major=<N>
    ...
    sudo rmmod chardev
    sudo dmesg | tail            # mychardev: unloaded

Note the module's on-disk/object name is `chardev` (from `chardev.ko`,
per the `Makefile`'s `obj-m += chardev.o`); the *device node* it creates
is named `mychardev` (from `DEVICE_NAME` in the source). `insmod`/`rmmod`
use the module name; the device path uses the device name.

## Read/write example

    echo "hello kernel" | sudo tee /dev/mychardev
    sudo cat /dev/mychardev      # hello kernel

Or, for an exact byte-for-byte round trip without a trailing newline
(what `scripts/test-chardev.sh` does):

    printf 'hello kernel' | sudo tee /dev/mychardev >/dev/null
    sudo cat /dev/mychardev; echo   # hello kernel

## Expected dmesg messages

    mychardev: loaded, major=<N>
    mychardev: unloaded

If `register_chrdev()`, `class_create()`, or `device_create()` fail
during load, the driver logs an error at `KERN_ERR`, unwinds anything it
already registered, and `insmod` reports the negative return code.

## Security and privilege considerations

- The device node's default permissions come from the kernel's default
  `udev` rules for `device_create()`-created nodes, which is typically
  root-only (`0600`) unless a udev rule on the system says otherwise —
  expect to need `sudo`/root for both write and read in the examples
  above.
- The driver performs no input validation beyond a length clamp; it is
  not a security boundary and should not be exposed to untrusted
  callers. It is intentionally scoped to local, single-host testing.
- Loading any out-of-tree module without a valid signature **taints the
  kernel** (visible in `/proc/sys/kernel/tainted` and in `dmesg`), which
  is expected and harmless for local development but worth knowing
  about before it shows up unexplained in a bug report.

## Correctness fixes applied in this update

The original driver worked for the documented single-user test case but
had three gaps, fixed without changing its external behavior or API:

- **No error checking on init.** `register_chrdev()`, `class_create()`,
  and `device_create()` can each fail (e.g. major-number exhaustion,
  allocation failure) and previously the return values were ignored,
  which could leave `chardev_init()` reporting success while the device
  was only partially set up. Each call is now checked, and any failure
  unwinds the steps already completed and returns the real error code
  to `insmod`.
- **No locking around the shared buffer.** `msg` is one buffer shared by
  every file descriptor; concurrent `read`/`write` from two processes
  could previously interleave a partial `copy_from_user()` with a
  concurrent `simple_read_from_buffer()`. A `struct mutex` now serializes
  access.
- **`read()` used `strlen(msg)`** to find the message length instead of
  tracking it explicitly. This happened to work for plain text but would
  under- or over-read if a write ever contained an embedded NUL. `read()`
  now uses the exact length recorded at write time.

## Known limitations

- Single global message buffer shared by all opens — there is no
  per-file-descriptor state, so two processes writing concurrently will
  race for whose message "wins" (the mutex only prevents corrupting the
  buffer mid-copy, it does not give each opener an independent buffer).
- No `ioctl`, `poll`/`select`, or `mmap` support.
- No persistence: the message is lost on module unload.
- Not tested against realtime/PREEMPT_RT kernels or non-x86 architectures.
- This is an educational driver, not a production or hardware driver.

## Tested kernel and compiler information

- Built and loaded against Linux 6.10 (this repository's custom kernel;
  see `kernel-build/README.md`) and, separately, against a Clang/LTO
  distribution kernel using `LLVM=1`.
- As part of this documentation update, the driver was re-compiled
  (`make LLVM=1`) against the headers of the machine's locally running
  kernel (a CachyOS 7.1.4 build, *not* the project's own Linux 6.10 tree)
  purely to confirm the source still builds cleanly after the
  correctness fixes below — it was not re-loaded (`insmod`) or
  functionally re-tested. Compilation against GCC, and any testing
  against a real Linux 6.10 build, is unverified by this update — see
  the repository root README's "Manual verification checklist."
