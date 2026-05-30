# Plan: Port CI VM Tests to Linux/KVM (Revised)

> Supersedes [LINUX-VMS.md](LINUX-VMS.md). Same goal, smaller plan: validation
> on a real Linux box (heritage.hellbent.app, 2026-05-28) showed that the
> Lima-on-Linux path with KVM acceleration works essentially unchanged. The
> custom QEMU/KVM backend the original plan proposed is not required.

ARCHIVE: See [LINUX-VM-2-ARCHIVE.md](LINUX-VM-2-ARCHIVE.md) for completed
V1-V12, Fixes 1-13, B8, the Phase 0/1/2/3 history, and the Boot-time
predictions vs actuals table.

NEXT ACTION: All phases done. Remaining work is the Backlog (B1-B7, B9).
B7 (fresh-Linux-host dry run + Migration doc) is the natural next target;
the others are non-blocking.

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

### B3: DragonFly's OVMF VARS template

The original macOS path was `edk2-i386-vars.fd`. Debian's `OVMF_VARS.fd`
should pair with `OVMF_CODE.fd` cleanly for x86_64, but this hasn't been
exercised against an actual DragonFly boot on Linux yet. If V6 fails on
firmware initialisation, try the `OVMF_*_4M.fd` variants or file a bug.

### B4: Image cache shared between hosts

Current scripts use `~/.lima/_cache/`. If we want a server-shared cache
(e.g. `/var/cache/ci-vms/`), make it configurable. Not blocking.

### B5: Stale hdiutil references in docs/comments

Functional code no longer uses `hdiutil` (Fix 2 swept it out of the
first-boot scripts and `solaris-test.sh`), but a few documentation/comment
references remain:

- `ci/README.md` lines 779, 781, 869, 871, 882: code examples showing the
  old hdiutil-based manual instance-id extraction. Replace with the
  `grep -aoE 'instance-id: [a-zA-Z0-9_-]+'` one-liner.
- `ci/dragonfly-first-boot.py:102`: docstring comment explaining *why* the
  script avoids hdiutil. Benign but reads oddly now that no script uses
  hdiutil at all — can be tightened.

Not blocking; just stale documentation.

### B6: Cosmetic — `==> Tested:` line shows unsubstituted `${TEST_MODULE}::VERSION`

Surfaced during V3 attempt 5. First version probe in all 5 `*-test.sh`:

```sh
_VERSION=$(limactl shell ... "perl -I'${GUEST_REPO}/lib' -M${TEST_MODULE} \
    -e 'print qq(${TEST_MODULE} \${TEST_MODULE}::VERSION\n)'" 2>/dev/null)
```

Result in V3 log: `==> Tested: IPC::Shareable ::VERSION` (the second
`${TEST_MODULE}` doesn't substitute because it's inside the perl single
quotes; only `\${TEST_MODULE}::VERSION` was meant to be the perl
expression, but `${TEST_MODULE}` should expand to `IPC::Shareable` first,
making it `$IPC::Shareable::VERSION`). The intent is fine — only the perl
expression rendering broke. Cosmetic only; test PASS/FAIL is unaffected.

### B7: Fresh-Linux-host dry run + "Migration to a new Linux machine" doc

After V4–V9 are green, do one clean-slate validation on a fresh Linux box
(or simulate by blowing away `~/.lima/*`, `~/.cache/lima/`, the cached
images under `~/.lima/_cache/`, and re-running the full V suite from
scratch). The goal is to surface any host dep / config step we've taken
for granted on heritage that wouldn't be present elsewhere.

Inputs to budget for:

- `qemu-system-x86`, `qemu-utils`, `xorriso`, `ovmf` from apt
- `kvm` group membership (logout/login required)
- Lima install per `ci/README.md`
- `python3` (standard on Ubuntu, but should be asserted)
- Both `ipc-shareable` and `async-event-interval` cloned as siblings
- DragonFly: user must source `~/.lima/_cache/dragonfly64.qcow2` (no public
  cloud image exists for DragonFly)

If the dry run uncovers a step that isn't already captured, add a
**"Migration to a new Linux machine"** section near the top of
`ci/README.md` (after the existing "Host setup" subsection) with the
exact commands. Cross-reference from B5 since the README cleanup is
adjacent work.

Done when: a previously untouched Linux x86_64 host can run
`./ci/vm-tests.sh -p ipc-shareable` (all targets) end-to-end with only
the steps documented in `ci/README.md`.

#### Running migration notes (feed into README during B7)

Captured as we go. Move into `ci/README.md` "Migration to a new Linux
machine" section when B7 lands.

- **Host packages**: `qemu-system-x86 qemu-utils xorriso ovmf` via apt
  (Fix 1 + Phase 0).
- **Group membership**: `sudo usermod -aG kvm "$USER"` then logout/login
  so `/dev/kvm` is readable by the user that runs the scripts.
- **Lima version pin**: validated against Lima 2.1.1 on Ubuntu 22.04
  x86_64. Newer versions may need re-validation if cidata or hostagent
  behaviour shifts.
- **Sibling repo layout**: `ipc-shareable` and `async-event-interval`
  must live as siblings under a shared parent directory. `*-test.sh`
  computes `HOST_REPO` via `${SCRIPT_DIR}/../..` and would fail noisily
  otherwise.
- **DragonFly qcow2 is host-provided**: no public cloud image exists.
  Copy `~/.lima/_cache/dragonfly64.qcow2` from an existing host that
  already has it (or build via the procedure in the README — TBD if
  one exists). `scp` ~778 MB.
- **Lima cidata.iso gap for OpenBSD config**: Lima 2.1.1 on Linux
  silently does not generate `cidata.iso` for `openbsd-lima.yaml`. Same
  Lima version does generate it on macOS for the same yaml. Worked
  around in `openbsd-test.sh` (Fix 7) by self-generating a minimal
  NoCloud ISO. No user-visible step required; just noting that the
  workaround is in place.
- **DragonFly OVMF on Debian/Ubuntu**: Debian's `/usr/share/OVMF/OVMF_CODE.fd`
  works for DragonFly out of the box. B3 (concern about VARS template
  compatibility) was a non-issue in V6 — the path resolver in
  `dragonfly-first-boot.py` finds it automatically. No user-visible step.
- **OpenBSD has no `unzip`, and doesn't need one**: the aei project on
  OpenBSD installs IPC::Shareable from a GitHub `.tar.gz` (extracted with
  the base-system `tar`) rather than the previous `.zip`+`unzip` flow.
  No package install required (Fix 10). User-visible only if you maintain
  the script — don't reintroduce a `unzip` dependency on the guest.
- **OmniOS qcow2 needs a one-time host-side pre-bake (Fix 13)**: a fresh
  download of `omnios-r151058.cloud.vmdk` boots so slowly on Linux KVM
  that it never finishes first-boot before the script gives up. Run this
  once on the host, after `solaris-test.sh` has downloaded and converted
  the image to `~/.lima/_cache/omnios-r151058.qcow2`:

  ```sh
  cp ~/.lima/_cache/omnios-r151058.qcow2 ~/.lima/_cache/omnios-r151058.qcow2.bak
  sudo modprobe nbd max_part=16
  sudo qemu-nbd --connect=/dev/nbd0 ~/.lima/_cache/omnios-r151058.qcow2
  sudo mkdir -p /mnt/omnios
  sudo zpool import -f -R /mnt/omnios rpool
  sudo zpool export rpool
  sudo qemu-nbd --disconnect /dev/nbd0
  sudo rmdir /mnt/omnios
  ```

  Required apt packages: `qemu-utils zfsutils-linux`. **Do not edit
  any files inside the pool** — see Fix 13 for why (boot archive
  checksum mismatch triggers an OmniOS auto-reboot that won't recover).
- **libguestfs needs readable kernel images on Debian/Ubuntu**: out of
  the box, `/boot/vmlinuz-*` is `-rw-------` (root-only). `sudo chmod
  644 /boot/vmlinuz-*` lets the regular user run `guestfish`,
  `virt-edit`, etc. Not strictly required for the OmniOS pre-bake
  (that uses `qemu-nbd`, not libguestfs), but useful for any future
  guest filesystem inspection. May need re-applying after kernel
  package upgrades.

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
