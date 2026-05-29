# Archive from 2026-05-28

This file holds work items from [LINUX-VMS-2.md](LINUX-VMS-2.md) that have
been completed and verified. Stable IDs (V1, V2, …; Fix 1, Fix 2, …) are
preserved here.

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
| V12 | async-event-interval on all VMs/Linux | From aei repo: `./ci/vm-tests.sh -f -o -d -l` (no `-s`, B8)    | All four non-Solaris VMs pass on aei project          | ✅ heritage 2026-05-29: PASS (3+ attempts). freebsd Files=41 Tests=676 perl 5.42.2; linux-i386 Files=41 Tests=699 perl 5.36.0 (i386 chroot); dragonfly Files=41 Tests=699 perl 5.36.3; openbsd Files=41 Tests=630 perl 5.36.1 (fewer due to OpenBSD-specific aei skips). All four IPC::Shareable installed cleanly (1.16 from cpanm on freebsd/dragonfly/linux-i386; 1.17 from GitHub tarball on openbsd). Three openbsd fixes uncovered along the way (Fix 10a/b/c — see main doc); these were latent in the openbsd `IPC_INSTALL=github` path that V12 was the first run to exercise. |
