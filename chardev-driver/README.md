# chardev-driver

A minimal Linux character-device driver used to demonstrate userspace ↔
kernel communication through the standard `read`/`write` VFS interface.

## What it does

`chardev.c` registers a character device named `mychardev` backed by a
fixed-size circular queue. The queue contains 16 slots, each with an exact
payload length and 256-byte data array. `head` identifies the oldest message,
`tail` identifies the next free slot, and `count` distinguishes empty from
full when the indices wrap.

- **write(2)** accepts up to 256 bytes, copies the bytes into the next free
  slot with `copy_from_user()`, and appends that message to the queue. Payloads
  are length-tracked and may contain NUL bytes. A larger write is reported as
  a short, 256-byte write. A write to a full queue returns `ENOSPC`.
- **read(2)** copies bytes from the oldest message with `copy_to_user()`.
  Messages are consumed in FIFO order. If the userspace buffer is smaller
  than the message, a queue-wide offset records progress and later reads
  continue that same message. The slot is removed only after its entire
  payload has been copied. Reading an empty queue returns 0.
- One `struct mutex` protects all queue indices, lengths, data, and the
  partial-read offset. The mutex remains held during userspace copies; unlike
  a spinlock it may sleep, and this prevents concurrent readers or writers
  from changing the active slot during a copy.

The fixed arrays mean the read and write paths perform no dynamic allocation.
There is deliberately no ioctl or per-open state: this is a teaching driver
for the VFS `file_operations` interface, not a general-purpose IPC mechanism.

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

`scripts/test-chardev.sh` in the repository root automates module loading and
tests a round trip, FIFO ordering, an embedded NUL with partial reads, full
queue rejection, reuse after draining, empty reads, and cleanup/unloading.

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

## Known limitations

- The queue is global across all opens and holds at most 16 messages. A full
  queue returns `ENOSPC`; an empty queue returns EOF rather than waiting.
- Partial-read progress is also global. Multiple readers safely consume one
  FIFO stream, but do not receive independent copies or independent cursors.
- Reads and writes do not block waiting for queue state, and the driver does
  not support `poll`/`select` or wait queues.
- No `ioctl` or `mmap` support.
- No persistence: the message is lost on module unload.
- Not tested against realtime/PREEMPT_RT kernels or non-x86 architectures.
- This is an educational driver, not a production or hardware driver.

## Tested kernel and compiler information

- Built and loaded against Linux 6.10 (this repository's custom kernel;
  see `kernel-build/README.md`) and, separately, against a Clang/LTO
  distribution kernel using `LLVM=1`.
- The historical kernel/compiler combinations above predate the ring-buffer
  change. Rebuild and run `scripts/test-chardev.sh` on a Linux test system to
  verify this revision at runtime.
