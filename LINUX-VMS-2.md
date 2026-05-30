# Plan: Port CI VM Tests to Linux/KVM (Revised)

> Supersedes [LINUX-VMS.md](LINUX-VMS.md). Same goal, smaller plan: validation
> on a real Linux box (heritage.hellbent.app, 2026-05-28) showed that the
> Lima-on-Linux path with KVM acceleration works essentially unchanged. The
> custom QEMU/KVM backend the original plan proposed is not required.

ARCHIVE: See [LINUX-VM-2-ARCHIVE.md](LINUX-VM-2-ARCHIVE.md) for completed
V1-V12, Fixes 1-13, B3 / B5 / B6 / B8, the Phase 0/1/2/3 history, and
the Boot-time predictions vs actuals table.

NEXT ACTION: B7's doc half is done (Migration section in `ci/README.md`).
The remaining half is the validation pass: a fresh-host run (or a
controlled wipe on heritage) to confirm the README's steps are
sufficient. B1, B2, B4, B9 remain in the backlog but are all non-blocking.

## How to maintain this doc (until we have a separate instructions file)

This doc is for **what's left to do**. Completed work moves to
`LINUX-VM-2-ARCHIVE.md`. A future AI session can pick up cold from this
doc + the ARCHIVE: pointer line, without reading the full archive.

- **As each V item, Fix, or B item completes**, move its entry verbatim
  into `LINUX-VM-2-ARCHIVE.md` and **delete it entirely from this doc**
  — no stubs, no "see archive" placeholder rows. The ARCHIVE: line
  below is the single source of truth for "what's been archived".
- **Completed multi-step plan sections** (Phase headers marked ✅ DONE,
  one-off validation tables, finished prediction tables) also move to
  the archive once they're settled. Keep this doc focused on
  forward-looking material: Goal, Architecture, "NOT doing" guardrails,
  active Backlog, and migration notes.
- **Then update the ARCHIVE: line above** to list the IDs / sections
  now in the archive. Readers shouldn't have to open the archive to
  know whether something is there.
- **Stable IDs persist**: never renumber on archive. V3 stays V3
  forever. New items still go at the end with the next free ID, never
  reused. (B8 is in the archive; the next backlog item is B9.)
- **Backlog items (B*)** stay in this doc until they're resolved or
  consciously dropped.
- **Fixes**: when none remain in this doc (the current state), don't
  keep an empty "Required fixes" heading. Future fixes get a fresh
  heading added back, then move out when complete.

## Goal

The CI scripts in `ipc-shareable/ci/` (used by both ipc-shareable and
async-event-interval) should work unchanged on either macOS or Linux. On
Linux x86_64, the existing TCG-emulated VMs (OpenBSD, Solaris, DragonFly,
linux-i386 host) move to native KVM. FreeBSD switches from aarch64 (macOS
HVF) to x86_64 (Linux KVM) — fast on both. Dual support is via auto-detection
at script-startup, not a custom backend abstraction.

## Architecture

Each `*-test.sh` script already calls `limactl`. Lima itself decides whether
to use HVF (macOS aarch64), HVF/x86 (macOS x86 — unused here), or KVM (Linux).
We don't need a backend layer — Lima is the backend.

The only platform-specific code paths are:

1. **The flua YAML bug workaround** in `freebsd-test.sh` (already exists;
   needs to be present on both OSes — currently is).
2. **First-boot scripts** that talk to QEMU directly via serial socket — these
   have macOS-specific bits (`hdiutil`, `/opt/homebrew/bin/...`).
3. **A handful of macOS-specific shell flags** (`sed -i ""`, `tar
   --no-mac-metadata`, `COPYFILE_DISABLE`) sprinkled across the scripts.

Fix those and the scripts run on both platforms.

## What we are explicitly NOT doing

These appeared in LINUX-VMS.md; the validation showed they aren't needed:

- **No custom QEMU/KVM backend** (`vm-backend.sh`). Lima abstracts this.
- **No backend API** (`vm_exists`, `vm_start`, etc.). Scripts keep calling
  `limactl` directly.
- **No `*-kvm.sh` config files** to replace the `*-lima.yaml` files. The
  YAML files stay.
- **No bare-metal i386 chroot on the host.** The original plan suggested
  skipping the VM on Linux x86_64 and running `systemd-nspawn` directly
  on the host. That breaks dual support (macOS still needs the VM). If we
  want this speedup later, it's a separate optimization, not part of the
  Linux port.

## Backlog

Non-blocking items to revisit. Stable IDs per the tracking convention.

### B1: Lima's cidata.iso is 281 MB on Linux vs ~10 KB on macOS

Works fine for first-boot (we use `grep -aoE`), but the size is suspicious
— probably `xorrisofs` padding to a block boundary, or Lima 2.1.1
inadvertently bundling nerdctl into the cidata. Not blocking. If it
bothers us later, file upstream or use a different mkisofs frontend.

### B2: FreeBSD flua YAML cloud-init bug exists on both platforms

Upstream Lima bug (1-space list indentation that FreeBSD's parser rejects).
Worth filing against Lima if not already known. Until fixed, the
`freebsd-first-boot.py` workaround stays.

### B4: Image cache shared between hosts

Current scripts use `~/.lima/_cache/`. If we want a server-shared cache
(e.g. `/var/cache/ci-vms/`), make it configurable. Not blocking.

### B7: Fresh-Linux-host dry run + "Migration to a new Linux machine" doc

**Doc half: ✅ DONE** (2026-05-29). The "Migration to a new Linux
machine" subsection now lives in `ipc-shareable/ci/README.md` directly
after **Host setup**. It covers sibling repo layout, DragonFly base
image sourcing, the OmniOS qcow2 pre-bake (with the do-NOT-edit
caveat), and optional libguestfs accessibility.

**Validation half: still to do.** A clean-slate run on a previously
untouched Linux x86_64 host (or a controlled wipe of `~/.lima/*`,
`~/.cache/lima/`, and the `_cache/` images on heritage). The goal is
to surface any step that's silently present on heritage but isn't
captured in the README. **Done when**: a fresh host can run
`./ci/vm-tests.sh -p ipc-shareable` (all targets including solaris)
end-to-end with only the steps documented in `ci/README.md`.

### B9: Image migration from macOS (optional speedup)

(Was "Phase 4" in earlier plan drafts; promoted to a backlog item
since it isn't blocking anything.) The Lima qcow2 disks already on a
Mac can be reused on Linux to skip the download-and-install ceremony
for OpenBSD (Vagrant box extraction) and DragonFly (manually-installed
image — no public source for fresh creation):

```sh
# On the Mac:
scp ~/.lima/_cache/openbsd7.qcow2 linux:~/.lima/_cache/
scp ~/.lima/_cache/dragonfly64.qcow2 linux:~/.lima/_cache/
# Also copy any per-VM disks if you want to skip first-boot:
scp -r ~/.lima/openbsd-ipc linux:~/.lima/
# The Lima SSH key is per-machine, so the VM's authorized_keys
# won't accept the Linux key unless you also copy ~/.lima/_config/.
# Easier: let first-boot re-run on Linux and inject the local key.
```

Not blocking; nice for skipping ~20 minutes of one-time downloads on
a fresh Linux host. Worth folding into B7's Migration doc.

### Loose ends from Phase 3

- Delete `LIMA-TEST.md` (Phase 0 scratch doc; no longer needed). May
  or may not exist in your tree.
- Delete `/tmp/freebsd-first-boot-linux.py` on heritage (live patched
  copy used during Phase 0; the in-repo `freebsd-first-boot.py` now
  supersedes it).
