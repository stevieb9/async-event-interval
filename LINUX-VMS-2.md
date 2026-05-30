# Plan: Port CI VM Tests to Linux/KVM (Revised)

> Supersedes [LINUX-VMS.md](LINUX-VMS.md). Same goal, smaller plan: validation
> on a real Linux box (heritage.hellbent.app, 2026-05-28) showed that the
> Lima-on-Linux path with KVM acceleration works essentially unchanged. The
> custom QEMU/KVM backend the original plan proposed is not required.

ARCHIVE: See [LINUX-VM-2-ARCHIVE.md](LINUX-VM-2-ARCHIVE.md) for completed V1-V12, Fixes 1-13, and B8.

NEXT ACTION: Phase 3 is ✅ done. Remaining work in this doc is the Backlog
section — B7 (fresh-Linux-host dry run + Migration doc) is the natural next
target; everything else is non-blocking.

## How to maintain this doc (until we have a separate instructions file)

- **As each V item or Fix completes**, move its entry (V-table row or full
  Fix section) verbatim into `LINUX-VM-2-ARCHIVE.md`, preserving the ✅
  marker, date stamps, attempt notes, and stable ID.
  longer in this document. Same with B sections
- Then **update the ARCHIVE: line above** to list the IDs now present in
  the archive. The line is the single source of truth for "what's been
  archived"; readers shouldn't have to open the archive to know.
- **Stable IDs persist**: never renumber on archive. V3 stays V3 forever.
  New items still go at the end with the next free ID, never reused.
- **Backlog items (B*)** stay in this doc until they're resolved or
  consciously dropped — only then archive (or delete).
- No fixes remain in this doc; all are in the archive. New fixes
  surfaced by future backlog work (e.g. B7) should be added back as
  numbered sections under a fresh "Required fixes" heading and moved
  out when complete.

## Goal

The CI scripts in `ipc-shareable/ci/` (used by both ipc-shareable and
async-event-interval) should work unchanged on either macOS or Linux. On
Linux x86_64, the existing TCG-emulated VMs (OpenBSD, Solaris, DragonFly,
linux-i386 host) move to native KVM. FreeBSD switches from aarch64 (macOS
HVF) to x86_64 (Linux KVM) — fast on both. Dual support is via auto-detection
at script-startup, not a custom backend abstraction.

## What Phase 0 validated

Run on a real Ubuntu 22.04 x86_64 box with Lima 2.1.1:

| Check | Result |
|---|---|
| Lima installable from upstream tarball | ✅ |
| `/dev/kvm` accessible (user in `kvm` group) | ✅ |
| `-machine q35,accel=kvm` appears in qemu cmdline | ✅ KVM confirmed |
| Guest reports `Hypervisor: KVMKVMKVM` (FreeBSD `sysctl hw.hv_vendor`) | ✅ |
| FreeBSD 14.3 x86_64 cold start (download + create + first boot) | ~1m49s |
| FreeBSD 14.3 x86_64 warm start | **17s** |
| `limactl shell freebsd-test -- uname -a` works post-first-boot | ✅ |
| FreeBSD flua YAML cloud-init bug | ⚠️ Present on Linux too |
| Lima 2.1.1 `--norock` issue with Debian `genisoimage` | ⚠️ Needs `xorriso` |

The 17s warm boot is comparable to FreeBSD aarch64 on macOS HVF — both
native virt. The big wins are still ahead on OpenBSD/DragonFly/Solaris
(currently 30-60s under TCG on macOS, expected ~10-15s under Linux KVM).

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

## Implementation order

Phase 0 is complete (Lima-on-Linux validated). What remains:

**Tracking convention.** Phase 3 (validation) and Backlog items use stable
prefixed IDs (`V1, V2, ...`; `B1, B2, ...`). Don't renumber on delete or
reorder; items can be referenced across sessions ("V5 done", "fix B2"). New
items go at the end with the next free ID, even if logically they belong
in the middle.

### Phase 1: portability fixes — minimum viable Linux support ✅ DONE

Smallest set of changes to make the FreeBSD CI work on a Linux box without
manual intervention:

1. ✅ Edit `freebsd-lima.yaml` per Fix 5 (multi-arch images).
2. ✅ Apply Fix 2 (`hdiutil` → `grep`) to `freebsd-first-boot.py`.
3. ✅ Add Fix 1 setup note to `ci/README.md`.
4. ✅ Add `xorriso` probe to `vm-tests.sh` (Linux-only; exits early with the
   install command if `xorrisofs` is missing).

After Phase 1: a Linux box can run `freebsd-test.sh` end-to-end. Verified on
heritage.hellbent.app (Ubuntu 22.04, Lima 2.1.1).

### Phase 2: port the other first-boot scripts ✅ DONE

5. ✅ Apply Fix 2 + Fix 3 to `openbsd-first-boot.py`.
6. ✅ Apply Fix 2 to `solaris-first-boot.py` + replace the inline hdiutil
   Python in `solaris-test.sh` with a `grep -aoE` one-liner.
7. ✅ Apply Fix 3 to `dragonfly-first-boot.py` (already had portable Fix 2).
   OVMF path resolution added: tries macOS Homebrew, Debian/Ubuntu, and
   Fedora/RHEL locations; exits with `sudo apt-get install ovmf` hint when
   none found.
8. ✅ Apply Fix 4 (`tar --no-mac-metadata`) to `linux-i386-test.sh`.

**Bonus, included in Phase 2**: the direct-QEMU scripts (`openbsd-`,
`dragonfly-first-boot.py`) hardcoded `-accel tcg`. Now they probe
`/dev/kvm` and use `-cpu host -accel kvm` when available, so the one-time
bootstrap on Linux benefits from KVM (otherwise OpenBSD/DragonFly first-boot
would still be TCG-slow even on a Linux KVM host).

Untested on real Linux hardware yet — exercised per the Phase 3 checklist
below.

### Phase 3: validate on Linux — ✅ DONE

All V1-V12 PASSED on heritage; see archive for individual rows.

**Cleanup after all V* pass:**

- Delete `LIMA-TEST.md` (Phase 0 scratch doc; no longer needed).
- Delete `/tmp/freebsd-first-boot-linux.py` on heritage (live patched copy
  used during Phase 0; the in-repo `freebsd-first-boot.py` now supersedes
  it).
- Update the **Boot-time predictions** table below with actuals from V1–V12 (most data already in the archive).

### Phase 4 (optional): image migration from macOS

The Lima qcow2 disks already on the Mac can be reused on Linux to skip the
download-and-install ceremony for OpenBSD (Vagrant box extraction) and
DragonFly (manually-installed image — no source for fresh creation):

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

Not blocking; nice for skipping ~20 minutes of one-time downloads.

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

## Boot-time predictions (verify during Phase 3)

These are predictions, not measurements. Replace with actuals once V1–V9
have been run.

| VM | macOS now (TCG) | Linux KVM expected | Notes |
|---|---|---|---|
| FreeBSD | ~7s (HVF aarch64) | 17s measured (x86_64) | Already validated (Phase 0) |
| OpenBSD | ~33s | ~10-15s | First TCG escape |
| Solaris | ~58s | ~15-20s | Slowest TCG VM currently |
| DragonFly | ~42s | ~12-15s | EDK2 OVMF path differs on Linux |
| linux-i386 chroot | ~29s | similar | Same nested chroot; no KVM benefit |

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

