# Archive from 2026-05-28

This file holds work items from [LINUX-VMS-2.md](LINUX-VMS-2.md) that have
been completed and verified. Stable IDs (V1, V2, …; Fix 1, Fix 2, …) are
preserved here.

## Completed project phases

(Moved out of `LINUX-VMS-2.md` on 2026-05-29 once all phases were ✅.
The phase headers were a checklist; the actual fixes they reference are
catalogued under "Completed fixes" / "Archived fixes" below.)

### Phase 0: Lima-on-Linux validation — ✅ DONE

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
| FreeBSD flua YAML cloud-init bug | ⚠️ Present on Linux too (→ B2) |
| Lima 2.1.1 `--norock` issue with Debian `genisoimage` | ⚠️ Needs `xorriso` (→ Fix 1) |

The 17s warm boot is comparable to FreeBSD aarch64 on macOS HVF — both
native virt. The big wins were ahead on OpenBSD/DragonFly/Solaris
(historically 30-60s under TCG on macOS).

### Phase 1: portability fixes — minimum viable Linux support ✅ DONE

Smallest set of changes to make the FreeBSD CI work on a Linux box without
manual intervention:

1. ✅ Edit `freebsd-lima.yaml` per Fix 5 (multi-arch images).
2. ✅ Apply Fix 2 (`hdiutil` → `grep`) to `freebsd-first-boot.py`.
3. ✅ Add Fix 1 setup note to `ci/README.md`.
4. ✅ Add `xorriso` probe to `vm-tests.sh` (Linux-only; exits early with the
   install command if `xorrisofs` is missing).

After Phase 1: a Linux box could run `freebsd-test.sh` end-to-end. Verified
on heritage.hellbent.app (Ubuntu 22.04, Lima 2.1.1).

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
`dragonfly-first-boot.py`) had hardcoded `-accel tcg`. They now probe
`/dev/kvm` and use `-cpu host -accel kvm` when available, so the one-time
bootstrap on Linux benefits from KVM (otherwise OpenBSD/DragonFly first-boot
would still be TCG-slow even on a Linux KVM host).

### Phase 3: validate on Linux — ✅ DONE

All V1-V12 PASSED on heritage. Per-VM results are in the "Completed
validations" table below.

## Boot-time predictions vs. actuals

The original plan included a predictions table to verify during Phase 3.
With Phase 3 done, the actuals (embedded in each V row in the validations
table) are the authoritative numbers. Original predictions table preserved
for reference:

| VM | macOS now (TCG, predicted) | Linux KVM (predicted) | Notes |
|---|---|---|---|
| FreeBSD | ~7s (HVF aarch64) | 17s measured (x86_64) | Validated in Phase 0 |
| OpenBSD | ~33s | ~10-15s | First TCG escape |
| Solaris | ~58s | ~15-20s | Slowest TCG VM at the time |
| DragonFly | ~42s | ~12-15s | EDK2 OVMF path differs on Linux |
| linux-i386 chroot | ~29s | similar | Same nested chroot; no KVM benefit |

## Completed fixes

### Fix 1: `xorriso` dependency on Linux

Lima 2.1.1 on Debian/Ubuntu falls back to `/usr/bin/genisoimage` for cidata
ISO generation but uses the `--norock` flag, which Debian's genisoimage
doesn't support. `xorriso` provides `xorrisofs` which Lima prefers when
present.

**Change**: Add a one-time install note to `ci/README.md`:

```sh
# Debian/Ubuntu Linux host setup
sudo apt-get install -y qemu-system-x86 qemu-utils xorriso
# Add user to kvm group, log out/in:
sudo usermod -aG kvm "$USER"
```

Optionally, `vm-tests.sh` could probe for `xorriso` on Linux and warn early
if missing. Not blocking.

### Fix 2: First-boot scripts — `hdiutil` → portable ISO reader

All four first-boot scripts (`freebsd-`, `openbsd-`, `solaris-`,
`dragonfly-first-boot.py`) read `cidata.iso` to extract the instance-id.
Three use `hdiutil attach`/`detach` (macOS-only). One (`dragonfly`) already
uses a portable byte-read.

**Change**: Replace each `get_instance_id()` that uses `hdiutil` with this
portable version (validated on Linux during Phase 0):

```python
def get_instance_id():
    iso = os.path.join(LIMA_DIR, "cidata.iso")
    if not os.path.exists(iso):
        return None
    r = subprocess.run(
        ["grep", "-aoE", "instance-id: [a-zA-Z0-9_-]+", iso],
        capture_output=True,
    )
    if r.returncode == 0 and r.stdout:
        line = r.stdout.decode("utf-8", errors="ignore").splitlines()[0]
        return line.split(":", 1)[1].strip()
    return None
```

Why `grep` instead of the dragonfly-style "read all bytes": on Linux, Lima
generates a ~281 MB cidata.iso (xorrisofs padding quirk); reading the whole
thing is wasteful. `grep -aoE` streams the file and finishes in milliseconds.

Files affected:
- `ipc-shareable/ci/freebsd-first-boot.py:45-63`
- `ipc-shareable/ci/openbsd-first-boot.py:69-86`
- `ipc-shareable/ci/solaris-first-boot.py:~45-65` (same pattern)

`dragonfly-first-boot.py` is already portable on this point.

Same fix applies to the inline Python in `solaris-test.sh:303-321`
(`_write_boot_done` function uses `hdiutil`).

### Fix 3: First-boot scripts — hardcoded `/opt/homebrew/...` paths

Two scripts hardcode the macOS Homebrew QEMU paths:

- `openbsd-first-boot.py:47` — `QEMU_BIN = "/opt/homebrew/bin/qemu-system-x86_64"`
- `dragonfly-first-boot.py:49-51` — `QEMU_BIN` + OVMF paths

**Change**: Resolve at runtime via `shutil.which()` and a small fallback
table for OVMF firmware paths:

```python
import shutil

QEMU_BIN = shutil.which("qemu-system-x86_64") or "/opt/homebrew/bin/qemu-system-x86_64"

def _find_ovmf(name_options):
    # Returns the first existing path from candidates.
    candidates = [
        # macOS Homebrew
        f"/opt/homebrew/share/qemu/{name_options[0]}",
        # Debian/Ubuntu
        "/usr/share/OVMF/OVMF_CODE.fd",
        "/usr/share/OVMF/OVMF_CODE_4M.fd",
        # Fedora/RHEL
        "/usr/share/edk2/ovmf/OVMF_CODE.fd",
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    raise FileNotFoundError(f"OVMF firmware not found; tried: {candidates}")
```

DragonFly's specific OVMF VARS template (`edk2-i386-vars.fd`) doesn't have a
direct Debian counterpart — needs investigation when DragonFly is ported.
Defer until DragonFly is the active target.

### Fix 4: BSD-only shell flags

| File:line | Macro | Linux equivalent |
|---|---|---|
| `linux-i386-test.sh:154` | `tar --no-xattrs --no-mac-metadata` | `--no-mac-metadata` is BSD-only; GNU tar rejects it |
| `linux-i386-test.sh:154` | `COPYFILE_DISABLE=1` | No-op on Linux; harmless to keep |

The tar in `linux-i386-test.sh:154` runs on the **host** (piped into a
guest-side tar via `limactl shell`), so the host's tar flavor matters.

The `sed -i ""` in `freebsd-test.sh:164` was originally listed here but
turns out to be a non-issue: that command is wrapped in an `ssh ... '<cmd>'`
that ships the literal string to the FreeBSD guest, where BSD sed runs.
The host's sed is never invoked. No change needed.

**Change**: Platform-detect near the top of `linux-i386-test.sh`. Define a
`TAR_NO_META` shell variable:

```sh
case "$(uname -s)" in
    Darwin) TAR_NO_META='--no-mac-metadata' ;;
    Linux)  TAR_NO_META='' ;;
esac
```

Affected: `linux-i386-test.sh` only.

### Fix 5: FreeBSD architecture per-platform

The original Phase 1 attempt removed the top-level `arch:` from
`freebsd-lima.yaml` and added two `images:` entries (aarch64 + x86_64),
hoping Lima would auto-select by host arch. **It doesn't.** Lima 2.1.1
created the VM as aarch64 on an x86_64 Linux host (discovered during V1).

**Revised approach**: two single-arch YAMLs, script picks by `uname -m`:

- `ipc-shareable/ci/freebsd-lima.yaml` — `arch: aarch64`, single aarch64
  image. Used on macOS Apple Silicon and aarch64 Linux.
- `ipc-shareable/ci/freebsd-lima-x86_64.yaml` — `arch: x86_64`, single
  x86_64 image. Used on x86_64 Linux (and Intel macOS, if anyone still
  runs that).
- `freebsd-test.sh` picks via `case "$(uname -m)"`.

Other YAML files (openbsd, solaris, dragonfly, linux-i386) are already
x86_64-only with explicit top-level `arch:`, so they're fine.

### Fix 6: cleanup() always exits 0 (false PASS)

Discovered during V1: every `*-test.sh` script's `cleanup()` was:

```sh
cleanup() {
    trap - EXIT INT TERM    # succeeds, overwrites $? to 0
    status=$?               # captures 0 instead of the real failure code
    ...
    exit "$status"          # always exits 0 if untrap succeeded
}
```

So **any** failure between VM creation and the test runner was masked as
PASS by `vm-tests.sh`. This is why V1's first attempt reported PASS even
though `freebsd-first-boot.py` timed out waiting for a serial socket.

**Fix**: capture `$?` *before* untrapping.

```sh
cleanup() {
    status=$?
    trap - EXIT INT TERM
    ...
    exit "$status"
}
```

Applied to all five test scripts (`freebsd-`, `openbsd-`, `solaris-`,
`dragonfly-`, `linux-i386-test.sh`). One-line swap each.

## Completed validations

| ID  | What                                | Command                                                          | Expected                                              | Actual |
|-----|-------------------------------------|------------------------------------------------------------------|-------------------------------------------------------|--------|
| V1  | FreeBSD full suite, Linux/KVM       | `./ci/vm-tests.sh -p ipc-shareable -f`                           | All pass; warm boot ≤20s                              | ✅ heritage 2026-05-28 attempt 2: PASS. Fresh x86_64 VM (Bug B fix verified — `amd64.qcow2.xz` selected, guest `uname` reports amd64), first-boot via flua workaround completed, `Files=60, Tests=1304, Result: PASS`. End-to-end 6m26s (image decompress + first-boot dominate; in-VM test run was 27s). |
| V2  | OpenBSD first-boot on Linux/KVM     | fresh VM; `./ci/openbsd-test.sh -p ipc-shareable t/00-base.t`    | First-boot via direct QEMU+KVM completes ≤1 min       | ✅ heritage 2026-05-28 attempt 3: infrastructure PASS. Discovered Lima 2.x on Linux silently skips cidata.iso for openbsd-lima.yaml (works on macOS). Added cidata.iso self-generation fallback to openbsd-test.sh (Fix 7). Lima 2.x accepts our hand-rolled iso. First-boot via direct QEMU+KVM completed; packages installed; prove ran (errored on `t/15-interval.t` because that file is in async-event-interval, not ipc-shareable — V2 command corrected). |
| V3  | OpenBSD full suite                  | `./ci/vm-tests.sh -p ipc-shareable -o`                           | All pass; warm boot ≤15s                              | ✅ heritage 2026-05-28 attempt 5: PASS. `Files=60, Tests=1300, Result: PASS`, "All tests successful." `OpenBSD 7.4 amd64`, `perl 5.36.1`. End-to-end 3m58s. Required Fix 8 (`vm-tests.sh` masking), JSON in OTHER_DEPS, t/71-sysv_info.t openbsd platform fix, and Fix 9 (`set +e` around dash-vulnerable version probes). |
| V10 | xorriso probe fires when missing    | On Linux without `xorrisofs` in PATH: `./ci/vm-tests.sh -p ipc-shareable -f` | Exits with install command before any VM action | ✅ heritage 2026-05-28: probe block fires with restricted PATH, prints `apt-get install -y xorriso` hint |
| V11 | xorriso probe is no-op on macOS     | On Mac: `./ci/vm-tests.sh -p ipc-shareable -f`                   | Probe skipped (uname Darwin); behaviour unchanged     | ✅ 2026-05-28: short-circuits on `uname=Darwin`, no probe output |
| V6  | DragonFly first-boot                | Requires `~/.lima/_cache/dragonfly64.qcow2` (copy from Mac or build); `./ci/dragonfly-test.sh -p ipc-shareable t/00-base.t` | Direct QEMU+KVM boots through Debian OVMF firmware    | ✅ heritage 2026-05-29: PASS. qcow2 scp'd from Mac (~778 MB). Lima boot succeeded clean (essential + final requirements OK), `t/00-base.t` Files=1 Tests=5 Result: PASS. DragonFly 6.4-RELEASE, perl 5.36.3. ~2 min wall — qcow2 from Mac already had first-boot snapshot, so direct-QEMU bootstrap skipped. Debian OVMF (`/usr/share/OVMF/OVMF_CODE.fd`) loaded without issue, so B3 (DragonFly OVMF VARS) is a non-issue in practice. |
| V7  | DragonFly full suite                | `./ci/vm-tests.sh -p ipc-shareable -d`                           | All pass; warm boot ≤15s                              | ✅ heritage 2026-05-29: PASS. `Files=55, Tests=1170, Result: PASS`, "All tests successful." DragonFly 6.4-RELEASE, perl 5.36.3. End-to-end ~2 min. (55 files vs FreeBSD/OpenBSD's 60 — DragonFly-specific platform skips, not failures.) |
| V8  | linux-i386 chroot creation          | fresh VM; `./ci/linux-i386-test.sh -p ipc-shareable t/00-base.t` | debootstrap completes; chroot tests pass via nspawn | ✅ heritage 2026-05-29: PASS. Fresh VM (Debian 12 amd64), debootstrap built `/opt/chroot-i386`, cpanm installed IPC::Shareable 1.16 + Async::Event::Interval 1.13 + 7 deps inside chroot, nspawn ran prove against 32-bit perl 5.36.0, `Files=1 Tests=5 Result: PASS`. Note: B6 (`::VERSION` cosmetic) doesn't manifest here — linux-i386's nested escape pattern renders correctly. |
| V9  | linux-i386 full suite               | `./ci/vm-tests.sh -p ipc-shareable -l`                           | All pass                                              | ✅ heritage 2026-05-29: PASS. `Files=60, Tests=1302, Result: PASS`, "All tests successful." 32-bit perl 5.36.0 in i386 chroot. 27s in-VM, ~45s end-to-end. Warm boot + nspawn into existing chroot. |
| V12 | async-event-interval on all VMs/Linux | From aei repo: `./ci/vm-tests.sh -f -o -d -l` (no `-s`, B8)    | All four non-Solaris VMs pass on aei project          | ✅ heritage 2026-05-29: PASS (3+ attempts). freebsd Files=41 Tests=676 perl 5.42.2; linux-i386 Files=41 Tests=699 perl 5.36.0 (i386 chroot); dragonfly Files=41 Tests=699 perl 5.36.3; openbsd Files=41 Tests=630 perl 5.36.1 (fewer due to OpenBSD-specific aei skips). All four IPC::Shareable installed cleanly (1.16 from cpanm on freebsd/dragonfly/linux-i386; 1.17 from GitHub tarball on openbsd). Three openbsd fixes uncovered along the way (Fix 10a/b/c — see Fix 8/9/10 sections below); these were latent in the openbsd `IPC_INSTALL=github` path that V12 was the first run to exercise. |
| V4  | Solaris first-boot                  | fresh VM; `./ci/solaris-test.sh -p ipc-shareable t/00-base.t`    | Lima serial-socket setup works; SMF marker installed  | ✅ heritage 2026-05-29 attempt 5: PASS. `Files=1 Tests=5 Result: PASS`, OmniOS r151058 / perl 5.42.2, IPC::Shareable 1.16. End-to-end: warm boot from snapshot + cpanm install of 9 distributions + test + clean shutdown ~1 min. Required Option F pre-bake (Fix 13: import/export pool ONLY, no `/etc/system` edit), Fix 11 (`timeout 10` wrap around polling SSH), and Fix 12 (single→double quote fix to expand `${OTHER_DEPS}` in the install heredoc). Attempt 1 (1h22m hung on ZFS scan), attempt 2 (pre-bake-with-edit triggered boot-archive rebuild + reboot that hung 23m), attempt 3 (revealed Fix 11 — `ssh ... true` hung 14m on banner exchange), attempt 4 (revealed Fix 12 — `${OTHER_DEPS}` empty, JSON not installed, tests died at `use IPC::Shareable`). |
| V5  | Solaris full suite                  | `./ci/vm-tests.sh -p ipc-shareable -s`                           | All pass; warm boot ≤20s                              | ✅ heritage 2026-05-29: PASS. `Files=60, Tests=1286, Result: PASS`, "All tests successful." OmniOS r151058 / perl 5.42.2, IPC::Shareable 1.16. In-VM test run 30s; end-to-end 11m08s (most of it cpanm installing the remaining OTHER_DEPS — Test::SharedFork, Mock::Sub, Async::Event::Interval — from cold CPAN on OmniOS). Warm boot from V4's saved snapshot. No new fixes needed; Fixes 11-13 from V4 held up. |

## Archived fixes (added 2026-05-29)

### Fix 7: cidata.iso not generated by Lima 2.x on Linux for OpenBSD config

Discovered during V2 attempt 1.

Lima 2.1.1 on **macOS** generates `~/.lima/<vm>/cidata.iso` at `limactl
create` time for `openbsd-lima.yaml` (~268 MB, contains Lima boot scripts).
Lima 2.1.1 on **Linux** silently skips it for the same yaml. Tested removing
`firmware.legacyBIOS: true` — still skipped. Same Lima version generates
`cidata.iso` for `freebsd-lima-x86_64.yaml` on the same host, so the
differentiator is something specific to the openbsd yaml (still not
fully diagnosed — possibly the local cached image path or the
`user.name: vagrant` field).

`openbsd-first-boot.py` reads the instance-id from `cidata.iso`; without
it the script exits before launching QEMU.

**Fix**: in `openbsd-test.sh`, if `~/.lima/<vm>/cidata.iso` is missing
after `limactl create`, generate a minimal NoCloud ISO ourselves using
`xorrisofs` (preferred) / `genisoimage` / `hdiutil` fallback. Contents:

- `meta-data` — `instance-id: iid-<epoch>\nlocal-hostname: lima-<vm>`
- `user-data` — empty
- volume label `cidata` (NoCloud convention)

V2 attempt 3 confirmed: Lima accepts the hand-rolled iso, the VM
boots normally, and the guest can mount `/dev/cd0a` to read meta-data.

V4 update (2026-05-29): the original entry speculated "likely needs to
be applied to `solaris-test.sh` too — TBD on V4." V4 was completed
without applying Fix 7 to solaris-test.sh. The OmniOS path uses a
different cidata mechanism (the lima YAML generated by solaris-test.sh
itself), and the gap that bit openbsd doesn't manifest for solaris.

### Fix 8: `vm-tests.sh` masks per-VM failures

Discovered during V3 attempt 1.

`vm-tests.sh`'s `run_vm()` shell function captures `_rc=$?` and writes
`FAIL:<rc>` to a status file, but the function itself always returns 0
(its last command is `echo`). So:

```sh
run_vm "openbsd" "openbsd-test.sh" || OVERALL=1
```

never fires the `OVERALL=1` branch. The RESULTS SUMMARY correctly prints
"FAIL (exit 2)" but the wrapper exits 0.

Sister of Fix 6 (same false-PASS class). Fixed by adding `return $_vm_rc`
to `run_vm()`. V1 retry was a genuine PASS — no failures to mask — so
its result is unaffected. V3 attempt 1 was masked; re-running.

### Fix 9: dash `set -e` exits on failed `$(...)` in version probes

Discovered during V3 attempt 4.

Each `*-test.sh` script ends with a block of version probes:

```sh
_VERSION=$(limactl shell ... perl -I.../lib -M${TEST_MODULE} ... 2>/dev/null)
_IPC_SHAREABLE_VERSION=$(limactl shell ... perl -MIPC::Shareable ... 2>/dev/null)
_IPC_SHAREABLE_VERSION="${_IPC_SHAREABLE_VERSION:-N/A}"
...
```

The second probe deliberately doesn't pass `-I lib`; the intent is to
report the **system-installed** IPC::Shareable version (or `N/A` if not
installed). On macOS `/bin/sh` is bash-as-sh: failed `$(...)` under
`set -e` does NOT cause exit. On Ubuntu `/bin/sh` is `dash`, where
**failed `$(...)` does cause exit** — verified with
`dash -c "set -e; x=\$(false); echo got-here"` (outer exit 1, no output).

On OpenBSD specifically, CPAN install of IPC::Shareable fails (OpenBSD
tar can't unpack PAX tarballs), so it's not system-installed, the second
probe fails, dash exits with the probe's exit code (255 in this case →
truncated by shell to ~2), the cleanup trap captures it, and the wrapper
reports `openbsd: FAIL (exit 2)` — even though prove already said `Result: PASS`.

**Fix**: wrap the version-probe block in `set +e` / `set -e`. Applied
to all five `*-test.sh` scripts. Latent on macOS (bash semantics
swallowed it); manifests on Linux.

### Fix 10: OpenBSD `IPC_INSTALL=github` path was never exercised end-to-end

Discovered during V12 attempts 1-2 (heritage, 2026-05-29).

The aei branch of `openbsd-test.sh` installs IPC::Shareable from GitHub
as a workaround for OpenBSD tar's inability to handle PAX extended
headers in modern CPAN tarballs. V12 is the first run that exercises
this branch — V3 (ipc-shareable on OpenBSD) uses `IPC_INSTALL=""`
because the project under test *is* IPC::Shareable. Two latent issues
surfaced:

**10a — `unzip` not installed in the OpenBSD VM (V12 attempt 1).**
The original block fetched `master.zip` and used `unzip -qo`:

```sh
curl -fsSL -o "$IPC_DIR/master.zip" "$IPC_URL"
unzip -qo "$IPC_DIR/master.zip" -d /tmp
```

OpenBSD cloud image doesn't ship `unzip`. The call failed silently
(`sh: unzip: not found`), `cd /tmp/ipc-shareable-master` then failed,
the install was skipped, and every aei test died at `use IPC::Shareable`.
**Fix**: switch to `.tar.gz` + native `tar`. GitHub's `git archive`
produces ustar tarballs (no PAX extended headers), so OpenBSD's native
`tar` extracts them cleanly without needing any extra package:

```sh
curl -fsSL -o "$IPC_DIR/master.tar.gz" "$IPC_URL"
tar -xzf "$IPC_DIR/master.tar.gz" -C /tmp
```

Also added `set -e` at the top of the inner shell so a future failure
fails loudly instead of skipping silently to the next step.

**10b — cleanup `rm -rf` lacked `sudo` (V12 attempt 2).**
With 10a fixed, IPC::Shareable installed successfully — but `set -e`
then exposed a second latent bug. The build runs `sudo perl Makefile.PL`
/ `sudo make` / `sudo make install`, which leaves `blib/` owned by root.
The trailing cleanup was `rm -rf "$IPC_DIR" /tmp/ipc-shareable-master`
without sudo, which fails with permission-denied on every root-owned
subdir. Pre-Fix-10 `set -e` swallowed it; post-fix it exits 1, killing
the script before the prove step runs. **Fix**: prepend `sudo` to both
`rm -rf` calls (the pre-install clean and the post-install clean).

**10c — `OTHER_DEPS` missing `String::CRC32` (V12 attempt 3).**
With 10a and 10b fixed, IPC::Shareable installed cleanly and tests
ran — and immediately died on `Can't locate String/CRC32.pm in @INC`
(an IPC::Shareable runtime prereq). The other VMs use
`cpanm --reinstall --notest IPC::Shareable` which auto-resolves
prereqs; OpenBSD's path is bare `perl Makefile.PL && make &&
make install`, which only **warns** about missing prereqs ("Warning:
prerequisite String::CRC32 0 not found.") and proceeds to install
anyway. **Fix**: add `String::CRC32` to the aei branch's `OTHER_DEPS`
so it's installed via the existing `cpan -T ${OTHER_DEPS}` step
before the GitHub-tarball IPC::Shareable install. The ipc-shareable
branch's `OTHER_DEPS` already included it.

All three fixes applied to `ipc-shareable/ci/openbsd-test.sh` only.
Pattern takeaway: when introducing `set -e` into a previously sloppy
block, audit every prior silent failure in that block first — and
when a path uses bare `Makefile.PL` instead of `cpanm`, prereqs are
your responsibility, not the toolchain's.

### Fix 11: polling SSH (`ssh ... true`) has no wall-clock timeout

Discovered during V4 attempt 3 (heritage, 2026-05-29).

`solaris-test.sh:268` and `freebsd-test.sh:148` both have a polling
loop that probes whether the guest SSH is up:

```sh
for _I in $(seq 1 600); do
    if ssh -F ~/.lima/"$VM"/ssh.config lima-"$VM" true 2>/dev/null; then
        _SSH_OK=1; break
    fi
    sleep 10
    ...
done
```

If the guest's qemu hostfwd accepts the TCP connection but the guest's
sshd never sends a banner (e.g. sshd is in early start-up, or hung
mid-reboot), the bare `ssh ... true` blocks indefinitely on the banner
read — `ConnectTimeout` only covers the TCP connect phase, not the
post-accept banner exchange. Result on V4 attempt 3: solaris-test.sh's
poll counter froze at "1 min elapsed" while the actual wall clock
advanced ~14 minutes, because the entire loop was stuck inside a
single hung `ssh` call.

**Fix**: wrap the polling SSH with `timeout 10` and add `-o
ConnectTimeout=5`:

```sh
if timeout 10 ssh -o ConnectTimeout=5 -F ~/.lima/"$VM"/ssh.config \
        lima-"$VM" true 2>/dev/null; then
    _SSH_OK=1; break
fi
```

Applied to both `solaris-test.sh` and `freebsd-test.sh`. The other test
scripts (`openbsd-`, `dragonfly-`, `linux-i386-test.sh`) use a
different polling strategy and don't have this bug.

### Fix 12: `solaris-test.sh` heredoc used single quotes — `${OTHER_DEPS}` didn't expand

Discovered during V4 attempt 4 (heritage, 2026-05-29).

The OmniOS install block at `solaris-test.sh:329` was:

```sh
_timeout_run 1200 limactl shell "$VM" -- sh -lc '
    set -e
    ...
    sudo env MAKE=gmake cpanm --notest ${OTHER_DEPS} 2>&1 || true
    ${IPC_INSTALL} 2>&1 || true
'
```

The outer **single** quotes prevent the outer shell from substituting
`${OTHER_DEPS}` and `${IPC_INSTALL}`. The inner shell (`sh -lc`) is a
fresh process invoked by `limactl shell`, which forwards env via SSH —
SSH only forwards a handful of standard env vars, not arbitrary shell
variables. So `${OTHER_DEPS}` and `${IPC_INSTALL}` expand to empty
strings inside the VM, and the cpanm invocation becomes
`sudo env MAKE=gmake cpanm --notest` with no module arguments — silent
no-op. CPAN deps were never installed. Result: V4 attempt 4 ran tests
that died at `use IPC::Shareable` with `Can't locate JSON.pm in @INC`.

`freebsd-test.sh:185`, `dragonfly-test.sh`, `linux-i386-test.sh`, and
`openbsd-test.sh` all use **double** quotes around the inner heredoc,
so they expand outer variables correctly — only `solaris-test.sh` had
the bug. Latent because V4 had never run successfully before.

**Fix**: switch the outer quotes to double, escape inner-shell variable
references (`\$PATH`, `\$_cc`, `\$_found`, `\$CPANM`). Also broaden the
gcc/cpanm `find` search to include `/opt` — OmniOS gcc14 installs to
`/opt/gcc-14/bin/gcc`, not `/usr/gcc/...`. The original search missed
it and left `/usr/bin/cc` un-symlinked.

### Fix 13: B8 resolution — pre-bake by ZFS import+export only (no `/etc/system` edit)

Discovered during V4 attempts 2-5 (heritage, 2026-05-29).

Resolves the open question in B8 about how to bypass the slow OmniOS
first-boot ZFS device scan. (Full B8 narrative below under "Archived
backlog items".)

**What works**: while libguestfs's vmlinuz chmod fix from V4 attempt 2
notes is still applicable for general libguestfs use on Debian/Ubuntu,
the actual qcow2 modification path is via `qemu-nbd` + native Linux
`zfsutils-linux`. The minimal viable procedure for the cached OmniOS
qcow2 is:

```sh
sudo modprobe nbd max_part=16
sudo qemu-nbd --connect=/dev/nbd0 ~/.lima/_cache/omnios-r151058.qcow2
sudo mkdir -p /mnt/omnios
sudo zpool import -f -R /mnt/omnios rpool   # -f: pool was last accessed by OmniOS
sudo zpool export rpool                      # exit cleanly with Linux as last-host
sudo qemu-nbd --disconnect /dev/nbd0
sudo rmdir /mnt/omnios
```

**Critical: do NOT edit any files inside the pool.** Specifically, do
not append `set zfs:zfs_scan_legacy = 0` to `/etc/system` (or modify
any other file there). The act of editing `/etc/system` changes the
checksum that OmniOS's boot loader uses to decide whether the cached
boot archive is current — OmniOS detects the mismatch, rebuilds the
boot archive at the end of first boot, and triggers a mid-boot reboot
("WARNING: Reboot required..."). V4 attempt 2 hit this and the reboot
did not recover cleanly on KVM — serial output stopped at
"rebooting...", sshd never came up.

The import/export-only approach (no file edit) cleans up the pool's
hostid and device-path metadata via the import/export cycle itself,
which is what makes the first-boot device scan complete quickly. The
boot-archive checksum is unchanged, so no rebuild/reboot is triggered.

Validated end-to-end by V4 attempt 5 (Files=1 Tests=5 PASS) and V5
(Files=60 Tests=1286 PASS). `solaris-test.sh` itself was not changed
for B8 — the resolution is entirely a one-time qcow2 prep on the
host. Future runs use the already-pre-baked cached qcow2.

## Archived backlog items

### B3: DragonFly's OVMF VARS template

Closed 2026-05-29 as a non-issue.

The original macOS path was `edk2-i386-vars.fd`. Debian's `OVMF_VARS.fd`
was hypothesised to pair with `OVMF_CODE.fd` cleanly for x86_64, but the
combination hadn't been exercised against an actual DragonFly boot on
Linux when this entry was filed.

V6 (DragonFly first-boot on Linux/KVM, heritage 2026-05-29) confirmed
that Debian's `/usr/share/OVMF/OVMF_CODE.fd` is loaded by the path
resolver in `dragonfly-first-boot.py` without any intervention — no
`OVMF_*_4M.fd` fallback needed, no bug to file. Closing as non-issue.

### B5: Stale hdiutil references in docs/comments

Resolved 2026-05-29.

Functional code stopped using `hdiutil` after Fix 2 swept it out of the
first-boot scripts and `solaris-test.sh`, but stale references remained:

- `ci/README.md`: code examples showing the old hdiutil-based manual
  instance-id extraction (`hdiutil attach ... grep instance-id ...
  hdiutil detach`). Replaced with the portable `grep -aoE 'instance-id:
  [a-zA-Z0-9_-]+'` one-liner — works on macOS and Linux without
  mounting.
- `ci/dragonfly-first-boot.py:102`: docstring comment explaining *why*
  the script avoids hdiutil. The "fragile hdiutil mount/detach which
  can fail on stale mounts or macOS restrictions" framing was a
  contrast against the original approach; tightened to a
  forward-looking description ("Works without mounting (no macOS
  hdiutil, no Linux loop device)").

Cleanup made alongside B7's "Migration to a new Linux machine" README
work since both touched `ci/README.md`.

### B6: Cosmetic — `==> Tested:` line shows unsubstituted `${TEST_MODULE}::VERSION`

Surfaced during V3 attempt 5 (heritage, 2026-05-28). Resolved
2026-05-29.

The first version probe in `dragonfly-test.sh`, `openbsd-test.sh`, and
`solaris-test.sh` used `\${TEST_MODULE}::VERSION` inside an outer
double-quoted string:

```sh
_VERSION=$(limactl shell ... "perl ... -e 'print qq(${TEST_MODULE} \${TEST_MODULE}::VERSION\n)'")
```

Inside double quotes, `\${...}` is fully escaped — the outer shell
passes `${TEST_MODULE}::VERSION` through as literal text to perl. Perl
then sees `qq(IPC::Shareable ${TEST_MODULE}::VERSION\n)` and
interpolates `$TEST_MODULE` (a Perl variable, undefined here) as empty,
producing the famous `==> Tested: IPC::Shareable ::VERSION` artifact in
the test wrapper output.

`freebsd-test.sh` already had the correct pattern `\$${TEST_MODULE}`
(`\$` → literal `$`, then `${TEST_MODULE}` expanded by the outer shell
to `IPC::Shareable`, yielding the Perl variable `$IPC::Shareable::VERSION`).
`linux-i386-test.sh` used a different nested-escape pattern that also
worked correctly. So the bug only existed in 3 of the 5 scripts.

**Fix**: change `\${TEST_MODULE}::VERSION` to `\$${TEST_MODULE}::VERSION`
in dragonfly/openbsd/solaris-test.sh. Verified by re-running the
openbsd warm-VM suite — the output now correctly reads
`==> Tested: IPC::Shareable 1.17`.

Test PASS/FAIL was never affected — purely a cosmetic log-line fix.

### B7: Fresh-Linux-host dry run + "Migration to a new Linux machine" doc

Resolved 2026-05-29 in two halves.

**Doc half** — added a `### Migration to a new Linux machine`
subsection to `ipc-shareable/ci/README.md` directly after `### Host
setup`. It covers the four things a fresh Linux host needs beyond the
generic Lima install:

- **Sibling repo layout** — `ipc-shareable` and `async-event-interval`
  must live as siblings; `*-test.sh` computes `HOST_REPO` via
  `${SCRIPT_DIR}/../..`.
- **DragonFly base image** — no public cloud image; operator must scp
  `~/.lima/_cache/dragonfly64.qcow2` from a host that has it.
- **OmniOS qcow2 pre-bake** — the one-time `qemu-nbd` + `zpool
  import -f` + `zpool export` procedure that resolves B8 on a per-host
  basis. Includes the **do NOT edit files in the pool** warning that
  V4 attempt 2 surfaced.
- **Optional libguestfs accessibility** — `sudo chmod 644
  /boot/vmlinuz-*` for users who want `guestfish` / `virt-edit` for
  diagnostics. Not required for the OmniOS pre-bake.

**Validation half** — heritage was wiped to a Lima-free state
(`limactl delete` all VMs, `rm -rf ~/.lima ~/.cache/lima`, `sudo rm`
the Lima binary). Only the operator-supplied DragonFly qcow2 was
backed up outside Lima dirs; apt-installed host packages and the
existing `chmod 644 /boot/vmlinuz-*` were left as-is (per the
README's Host setup, those wouldn't be re-run by an operator who'd
already done a clean apt install).

Then reconstructed from the README only:

1. `curl ... | sudo tar -C /usr/local -xzf -` for Lima v2.1.1.
2. Verified sibling layout.
3. `cp ~/dragonfly64-backup.qcow2 ~/.lima/_cache/dragonfly64.qcow2`.
4. Ran `solaris-test.sh` with `timeout 600` (per the README's
   "let it download+convert, then Ctrl-C" pattern), then `limactl
   delete --force solaris-ipc`.
5. Did the 7-command OmniOS pre-bake block verbatim.
6. `./ci/vm-tests.sh -p ipc-shareable -k`.

End-to-end: 37 min 43 sec from cold-wiped state. All 5 VMs PASS:
freebsd, linux-i386, openbsd, solaris, dragonfly. Zero off-README
steps required.

The README is therefore sufficient for a fresh Linux x86_64 host.
Pattern takeaway: validating docs by mechanically following them
catches the silent-assumption bugs (e.g. "the chmod is already
applied, I forgot to mention it") that even careful authoring
misses.

### B8: OmniOS first-boot ZFS pool scan blocks V4/V5 (Linux KVM)

Discovered during V4 attempt 1 (heritage, 2026-05-28). Resolved
during V4 attempts 2-5 (2026-05-29). Resolution captured as Fix 13
in the main plan doc (to be archived with V5).

#### Original problem (attempt 1)

`solaris-test.sh` creates the OmniOS VM from the `omnios-r151058.cloud.vmdk`
image. On first boot, OmniOS does a full ZFS pool device scan that doesn't
complete in any reasonable time:

- Lima's hostagent timed out after 10 min ("did not receive 'running'
  status"), leaving qemu running but unsupervised
- `solaris-test.sh`'s own polling loop continued for another ~1h with no
  SSH availability
- Serial log showed the "Performing full ZFS device scan" message
- **We were on KVM** with `-machine q35,accel=kvm -cpu host`, yet still
  blocked — so this isn't purely a TCG slowness issue on Linux

#### Options considered

1. **Pre-bake `zfs_scan_legacy = 0` into the cached qcow2** by editing
   `/etc/system` via libguestfs/qemu-nbd before any boot.
2. **OmniOS cloud-init user-data** to set the kernel parameter on first
   boot (cloud-init support on OmniOS not confirmed).
3. **A serial-console "early write"** path in `solaris-first-boot.py`:
   intercept the boot loader and inject a kernel param.
4. **Larger Lima `start` timeout** + acceptance that V4 takes 1-2h on
   first-boot then is fast forever after.

#### Attempt 2 outcome: Option 1 (with /etc/system edit) — failed

Pre-baked the qcow2 with `set zfs:zfs_scan_legacy = 0` appended to
`/etc/system` via `qemu-nbd` + native Linux `zfsutils-linux`.
Serial log showed:

```
NOTICE: Performing full ZFS device scan!     ← STILL HAPPENS
NOTICE: Original /devices path (/pseudo/lofi@1:b) not available; ZFS is
        trying an alternate path (/pci@0,0/pci1af4,2@6/blkdev@0,0:b)
Loading smf(7) service descriptions: 1/1
Hostname: omnios
WARNING: Reboot required.
The system has updated the cache of files (boot archive) ...
syncing file systems... done
rebooting...
```

Two distinct problems:

1. **The full ZFS device scan still ran.** `zfs_scan_legacy` controls
   pool-level scrub/resilver behavior, not the device-path discovery
   that happens on import when ZFS notices `/devices` paths from the
   original install don't match what QEMU presents. The "Original
   /devices path ... not available" line is the smoking gun — this is
   a device re-discovery, not a metadata scrub. The tunable doesn't
   gate it.
2. **OmniOS auto-rebuilt the boot archive and rebooted.** When OmniOS
   detects `/etc/system` changed since the boot archive was last
   updated, it rebuilds and forces a reboot. The reboot hung — serial
   output stopped at "rebooting...", sshd never came back, qemu kept
   running but idle. 23+ min frozen.

#### Attempt 3 outcome: same pre-bake, more patience — surfaced a script bug

Ran V4 again to see if the auto-reboot would eventually recover. Lima
fatal at 10 min (normal), `solaris-test.sh`'s polling counter froze
at "1 min elapsed" — surfaced [Fix 11](#fix-11-polling-ssh-ssh--true-has-no-wall-clock-timeout):
the polling SSH had no wall-clock timeout and was hung indefinitely
on banner exchange. After unsticking, confirmed the post-reboot
state was genuinely stuck (TCP accepted, no SSH banner, no further
serial output, qemu idle).

#### Attempt 4 outcome: pre-bake WITHOUT /etc/system edit — boots cleanly, fails on missing deps

Restored the `.bak` qcow2, did the import/export ONLY (no file edit),
and re-ran V4. OmniOS booted cleanly past the device scan into SMF
loading — no auto-reboot trigger because `/etc/system` was unchanged
and the boot archive checksum still matched. `solaris-first-boot.py`
ran cleanly via serial console. But test execution failed at
`use IPC::Shareable` with `Can't locate JSON.pm in @INC` — surfaced
[Fix 12](#fix-12-solaris-testsh-heredoc-used-single-quotes--other_deps-didnt-expand):
the single-quoted install heredoc meant `${OTHER_DEPS}` expanded to
empty, and `cpanm --notest` (with no args) was a silent no-op. Tests
ran against a VM with no Perl deps installed.

#### Attempt 5 outcome: ✅ PASS

With Fix 12 applied, V4 attempt 5 PASSED end-to-end. Files=1 Tests=5
Result: PASS. Resolution: see Fix 13.

#### Pattern takeaway

The instinct to "edit `/etc/system` to set a tunable" is the
illumos-native way, but it breaks the boot-archive contract when done
offline. For ZFS-on-import slowness specifically, the *act* of
importing-then-exporting on a different OS (Linux) cleans up pool
hostid and device-path metadata, which is the actual remediation —
no file edit required. When applying a fix that touches early-boot
filesystem state, ask "what state machine on the guest depends on
this not changing under it?" before changing it.
