# docs/assets

Evidence images/logs referenced from the root README's "Evidence"
section belong here. None currently exist in this repository — this
directory is a placeholder until they are captured by hand, following
`../evidence-checklist.md`.

## Files expected here (add as they're captured)

| Suggested filename | Evidence |
|---|---|
| `qemu-boot-success.png` | QEMU booting to a BusyBox shell prompt |
| `uname-a.png` (or `.txt`) | `uname -a` output from inside the booted guest |
| `chardev-load-dmesg.png` (or `.txt`) | `dmesg` after `insmod chardev.ko` |
| `chardev-read-write.png` (or `.txt`) | Write-then-read-back of `/dev/mychardev` |
| `gdb-breakpoint.png` (or `.txt`) | GDB stopped at `start_kernel` |
| `gdb-backtrace.png` (or `.txt`) | `bt` output at the breakpoint |

Plain-text terminal captures (`.txt`) are equally acceptable evidence
and are easier to keep accurate over time than screenshots — use
whichever is convenient. Do not add placeholder or fabricated images;
an empty checklist item in `../evidence-checklist.md` is preferable to
a fake screenshot.
