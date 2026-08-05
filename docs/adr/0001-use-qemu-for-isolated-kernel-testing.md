# Use QEMU for isolated kernel testing

## Status

Accepted

## Context

Testing a custom-built kernel by booting it directly on the host
hardware risks an unbootable or misbehaving kernel taking down the
development machine, and makes iteration slow (reboot cycles, no easy
way to attach a debugger before userspace starts).

## Decision

Boot and test the custom kernel inside QEMU (`qemu-system-x86_64`)
rather than on bare metal. QEMU provides a disposable virtual machine,
a serial console for headless output, and a built-in GDB remote stub
(`-s -S`) for attaching a debugger from the very first instruction.

## Consequences

- Fast, safe iteration: a bad kernel just fails to boot a VM, not the
  host.
- QEMU's virtual CPU model is not identical to the host CPU by default
  (`qemu64`), which surfaced its own compatibility issue — see the
  root README's "Technical challenges" table and `-cpu max`.
- Findings are validated against a virtual machine, not real hardware;
  this project makes no claim about behavior on physical devices.
