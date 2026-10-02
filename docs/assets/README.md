# docs/assets

Evidence images and logs referenced by the root README belong here. The
repository includes `gdb-start-kernel.png`, a terminal-style rendering of the
real session preserved in `../../qemu-gdb/notes.md`. It is a presentation of
that recorded transcript, not a claim that the session was rerun during the
portfolio cleanup.

## Files expected here (add as they're captured)

| Suggested filename | Evidence |
|---|---|
| `qemu-boot-success.png` | QEMU booting to a BusyBox shell prompt |
| `uname-a.png` (or `.txt`) | `uname -a` output from inside the booted guest |
| `chardev-load-dmesg.png` (or `.txt`) | `dmesg` after `insmod chardev.ko` |
| `chardev-read-write.png` (or `.txt`) | Write-then-read-back of `/dev/mychardev` |
| `gdb-start-kernel.png` | Existing rendering of GDB stopped at `start_kernel` |
| `gdb-backtrace.png` (or `.txt`) | `bt` output at the breakpoint |

Plain-text terminal captures (`.txt`) are equally acceptable evidence
and are easier to keep accurate over time than screenshots — use
whichever is convenient. Do not add placeholder or fabricated images;
an empty checklist item in `../evidence-checklist.md` is preferable to
a fake screenshot.
