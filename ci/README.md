# CI Test Runners

Scripts for running Async::Event::Interval tests inside local VMs via
[Lima](https://lima-vm.io/) and QEMU.

## Contents

- [Lima basics](#lima-basics)
- [Unified test runner (`vm-tests.sh`)](#unified-test-runner-vm-testssh)
- [FreeBSD CI](#freebsd-ci)
- [OpenBSD CI](#openbsd-ci)
- [Linux i386 CI](#linux-i386-ci)
- [OmniOS CE (Solaris) CI](#omnios-ce-solaris-ci)

## Lima basics

[Lima](https://lima-vm.io/) launches Linux (and experimentally, non-Linux) VMs
on macOS via QEMU, with automatic file sharing and port forwarding.

### Commands

```bash
limactl list                         # show all VMs and their status
limactl create --name <name> <yaml>  # create a VM from a template
limactl start <name>                 # start a VM
limactl stop <name>                  # clean shutdown (ACPI)
limactl stop --force <name>          # force-stop (SIGKILL to QEMU)
limactl shell <name>                 # open a shell inside the VM
limactl shell <name> -- <cmd>        # run a command inside the VM
limactl delete <name>                # delete VM and its disk image
```

### Directory layout

| Path | Purpose |
|------|---------|
| `~/.lima/<name>/lima.yaml` | VM instance config (editable between starts) |
| `~/.lima/<name>/ssh.config` | SSH config for `ssh -F` or `scp -F` |
| `~/.lima/<name>/disk` | VM disk image (QCOW2 on QEMU) |
| `~/.lima/<name>/serial.log` | Serial console log |
| `~/.lima/<name>/serial.sock` | QEMU serial console Unix socket |
| `~/.lima/_config/user` | SSH private key for all Lima VMs |
| `~/.lima/_config/user.pub` | SSH public key |
| `~/.lima/_cache/` | Downloaded image cache (shared across VMs) |

### SSH

Lima generates an SSH keypair at `~/.lima/_config/user*` and injects the public
key into each guest. Use the per-VM `ssh.config` to connect:

```bash
ssh -F ~/.lima/<name>/ssh.config lima-<name>
scp -F ~/.lima/<name>/ssh.config -r <src> lima-<name>:<dst>
```

`limactl shell <name>` wraps this with the correct flags automatically.

### Templates (`ci/*-lima.yaml`)

Each template declares the OS, architecture, CPU/memory/disk resources, and
the base disk image. `limactl create` copies the template into
`~/.lima/<name>/lima.yaml` and provisions the disk. After creation, you can
edit the VM's YAML directly (e.g. to bump CPUs) and `limactl start` will pick
up the changes.

### VM defaults and reuse

The default VM names (`freebsd-ipc`, `openbsd-ipc`, `linux-i386`, `solaris-ipc`)
match those used by the sibling `ipc-shareable` repo, so the same provisioned
VM disks can be reused between projects without re-downloading base images or
re-running first-boot bootstraps. Each test script installs any extra CPAN
deps the suite needs on top of what is already present, idempotently.

To use isolated VMs instead, set `VM=<name>` when invoking any script:

```bash
VM=freebsd-aei ./ci/freebsd-test.sh
```

## Unified test runner (`vm-tests.sh`)

Runs tests on one or more VMs sequentially and prints a summary with failed
test details.

```bash
./ci/vm-tests.sh [options] [prove options]
```

### Options

| Flag | Description |
|------|-------------|
| `-f`, `--freebsd` | Run FreeBSD tests |
| `-l`, `--linux` | Run 32-bit Linux (i386) tests |
| `-o`, `--openbsd` | Run OpenBSD tests |
| `-s`, `--solaris` | Run Solaris/OmniOS tests |
| `-a`, `--all` | Run all VMs (default) |
| `-k`, `--keep-logs` | Keep log files after the run |
| `-D`, `--display` | Write output to stdout instead of log files |
| `-h`, `--help` | Print usage and exit |

Prove options are forwarded to each VM test script (default: `-v t`).

### Examples

```bash
./ci/vm-tests.sh                              # all VMs, full suite
./ci/vm-tests.sh -s                           # Solaris only
./ci/vm-tests.sh -f -l t/15-interval.t        # FreeBSD + Linux, single test
./ci/vm-tests.sh -ks                          # Solaris only, keep logs
```

### Output

Each VM's output is logged to `/tmp/vm-tests-<timestamp>/<label>.log`.
Logs are deleted on exit unless `-k` is passed. After all VMs finish, a
summary table shows PASS/FAIL per VM, and failed test details are extracted
from each log.

---

## FreeBSD CI

Local FreeBSD testing via Lima and QEMU.

### One-time VM setup

Create and start the VM from the project's Lima template:

```bash
limactl create --name freebsd-ipc ci/freebsd-lima.yaml
limactl start freebsd-ipc
```

`freebsd-lima.yaml` provisions a FreeBSD 14.3 aarch64 VM with the base Perl
packages pre-installed.

### Logging into the VM

```bash
limactl shell freebsd-ipc
```

Or with SSH directly:

```bash
ssh -F ~/.lima/freebsd-ipc/ssh.config lima-freebsd-ipc
```

### Shutting down the VM

```bash
limactl stop freebsd-ipc
```

To permanently remove the VM and its disk image:

```bash
limactl delete freebsd-ipc
```

### Running the test suite

`freebsd-test.sh` starts the VM (if not already running), copies the source,
runs the test suite, then stops the VM automatically on exit — whether the
tests pass, fail, or the script is interrupted.

```bash
./ci/freebsd-test.sh [options] [prove options]
```

**Options:**

- `--perl-version <ver>` — Build and test with a specific Perl version
  managed by perlbrew (e.g. `5.20.3`). Compiles Perl from source on the
  first run (10-20 min); subsequent runs reuse the cached build. Useful
  for reproducing failures reported against older Perl versions.
- `-h`, `--help` — Print usage and exit.

By default this runs `prove -l -v t` inside the VM. Pass your own prove
arguments to override:

```bash
./ci/freebsd-test.sh t/15-interval.t                       # single test file
./ci/freebsd-test.sh -v t/15-interval.t                    # verbose, single file
./ci/freebsd-test.sh t                                     # whole suite, no -v
./ci/freebsd-test.sh --perl-version 5.20.3                 # full suite, Perl 5.20.3
./ci/freebsd-test.sh --perl-version 5.20.3 t/15-interval.t # single file, Perl 5.20.3
```

To target a different (already-created) Lima VM, set the `VM` variable:

```bash
VM=my-other-freebsd ./ci/freebsd-test.sh
```

> **Note:** If the VM does not yet exist, `freebsd-test.sh` will create it
> from `ci/freebsd-lima.yaml` automatically. The first run is slower for
> two reasons:
>
> 1. The disk image is downloaded (~770 MB, cached after the first download).
> 2. Lima's cloud-init YAML is incompatible with FreeBSD's built-in YAML
>    parser, so user/SSH setup must be done via the serial console instead.
>    `freebsd-test.sh` detects this automatically and runs
>    `ci/freebsd-first-boot.py`, which logs in through the QEMU serial
>    console, creates the SSH user, and installs a small rc.d service that
>    writes Lima's boot-done marker on every subsequent boot. This one-time
>    setup takes a few minutes. After it completes, later starts are fast.

---

## OpenBSD CI

Local OpenBSD testing via Lima and QEMU. Targets the CPAN smoker platform:

- `osname=openbsd`, `osvers=7.8`, `archname=OpenBSD.amd64-openbsd`

OpenBSD does not publish pre-built cloud images, so this setup uses the
`generic/openbsd7` Vagrant box (Roboxes). The QCOW2 is extracted once and
cached at `~/.lima/_cache/openbsd7.qcow2`.

Lima has no OpenBSD OS type. The config uses `os:FreeBSD` so that Lima waits
for the file-based boot-done marker instead of the Linux guest agent.
`openbsd-first-boot.py` bootstraps the VM via the QEMU serial console and
installs an rc.d service that writes the marker on every subsequent boot.

### One-time VM setup

Done automatically by `openbsd-test.sh`. To do it manually:

```bash
limactl create --name openbsd-ipc ci/openbsd-lima.yaml
limactl start openbsd-ipc
```

> **Note:** The first run downloads the Vagrant box (~1.1 GB) and extracts the
> QCOW2. This is cached in `~/.lima/_cache/` for subsequent runs. The first
> boot also runs `openbsd-first-boot.py` via the serial console to install the
> Lima SSH key and the boot-done rc.d service (one-time, takes ~1-2 minutes).

### Logging into the VM

```bash
limactl shell openbsd-ipc
```

Or with SSH directly:

```bash
ssh -F ~/.lima/openbsd-ipc/ssh.config lima-openbsd-ipc
```

### Shutting down the VM

```bash
limactl stop openbsd-ipc
limactl delete openbsd-ipc       # also removes disk image
```

### Running the test suite

`openbsd-test.sh` follows the same lifecycle as `freebsd-test.sh`: create VM
if absent, start it, run first-boot setup on the first run, copy source, run
tests, stop the VM on exit.

```bash
./ci/openbsd-test.sh [options] [prove options]
```

**Options:**

- `-h`, `--help` — Print usage and exit.

Same prove argument override syntax applies:

```bash
./ci/openbsd-test.sh t/15-interval.t
./ci/openbsd-test.sh t

VM=my-other-openbsd ./ci/openbsd-test.sh
```

> **Note:** The first run is slow for two reasons:
>
> 1. The Vagrant box is downloaded (~1.1 GB; the extracted QCOW2 is cached
>    at `~/.lima/_cache/openbsd7.qcow2` for subsequent runs).
> 2. The first boot runs `openbsd-first-boot.py` via the QEMU serial console
>    to install the Lima SSH key and a persistent boot-done rc.d service.
>    Subsequent starts are fast.
>
> **Crash recovery:** After a crash (kernel panic, force-stop), OpenBSD runs
> fsck at boot, which is slow under QEMU TCG emulation. The test script
> mitigates this in three ways:
>
> - On shutdown, it SSHs in and runs `doas shutdown -h now` before falling
>   back to `limactl stop`, so the filesystem is almost always clean.
> - After every clean shutdown, it saves a `qemu-img` snapshot on the VM's
>   QCOW2 disk. On the next start, the snapshot is reverted so that the
>   filesystem is never dirty, regardless of how the previous run ended.
> - During `limactl start`, the serial console log is monitored and a warning
>   is printed if fsck is detected (in case both mitigations fail).
>
> If the snapshot itself becomes corrupted, delete and recreate the VM:
> ```bash
> limactl stop --force openbsd-ipc; limactl delete openbsd-ipc
> # Then re-run the test script — it will recreate and provision automatically:
> ./ci/openbsd-test.sh
> ```

---

## Linux i386 CI

Local 32-bit Linux testing via Lima and QEMU.

Modern Debian and Ubuntu no longer publish i386 cloud images, so this setup
uses a Debian 12 (Bookworm) amd64 host VM. On the first run,
`linux-i386-test.sh` creates an i386 debootstrap chroot inside the VM and
installs 32-bit Perl + dependencies there. Tests run inside the chroot via
`systemd-nspawn`. The x86_64 kernel (even when QEMU-emulated on Apple
Silicon) natively executes 32-bit i386 binaries, so this exercises real
32-bit Perl with 32-bit integers and pointers.

The chroot is preserved between runs; only the source tree is re-copied.

### One-time VM setup

Done automatically by `linux-i386-test.sh`. To do it manually:

```bash
limactl create --name linux-i386 ci/linux-i386-lima.yaml
limactl start linux-i386
```

### Logging into the VM

```bash
limactl shell linux-i386
```

Or with SSH directly:

```bash
ssh -F ~/.lima/linux-i386/ssh.config lima-linux-i386
```

To get a shell inside the i386 chroot:

```bash
limactl shell linux-i386 -- sudo systemd-nspawn -D /opt/chroot-i386
```

### Shutting down the VM

```bash
limactl stop linux-i386
limactl delete linux-i386       # also removes disk image
```

### Running the test suite

`linux-i386-test.sh` follows the same lifecycle as `freebsd-test.sh`: create
VM if absent, start it, set up the i386 chroot on the first run, copy source,
run tests in the chroot, stop the VM on exit.

```bash
./ci/linux-i386-test.sh [options] [prove options]
```

**Options:**

- `-h`, `--help` — Print usage and exit.

Same prove argument override syntax applies:

```bash
./ci/linux-i386-test.sh t/15-interval.t
./ci/linux-i386-test.sh t

VM=my-other-linux ./ci/linux-i386-test.sh
```

> **Note:** The first run is slow (~5-10 min) because it downloads the amd64
> VM image, runs debootstrap to build the i386 chroot, and installs Perl
> packages via cpanm. Subsequent runs only re-copy the source and are much
> faster.

---

## OmniOS CE (Solaris) CI

Local Solaris testing via Lima and QEMU. Targets the CPAN smoker platform:

- `osname=solaris`, `osvers=2.11`, `archname=i86pc-solaris-64`
- `uname: SunOS 5.11 omnios-r151034`

OmniOS CE is the closest freely available match (illumos kernel, same SysV
IPC implementation). The VM runs OmniOS r151058 (current stable).

Lima has no illumos/Solaris OS type. The config uses `os:FreeBSD` so that
Lima waits for the file-based boot-done marker instead of the Linux guest
agent. `solaris-first-boot.py` bootstraps the VM via the QEMU serial console
and installs an SMF service that writes the marker on every subsequent boot.

OmniOS is x86-64 only. On Apple Silicon, QEMU emulates x86-64 via TCG
(software emulation) — the first boot takes 10-20 minutes. Subsequent
starts are much faster once the boot-done SMF service is installed.

### One-time VM setup

Done automatically by `solaris-test.sh`. Manual creation is not recommended:
the OmniOS image is a VMDK, which Lima cannot resize directly. The script
handles this by downloading the VMDK, converting it to QCOW2 (cached at
`~/.lima/_cache/omnios-r151058.qcow2`), and passing a rewritten YAML to
`limactl create`. Running `limactl create` with `solaris-lima.yaml` directly
will fail at the disk-resize step.

### Logging into the VM

```bash
limactl shell solaris-ipc
```

Or with SSH directly:

```bash
ssh -F ~/.lima/solaris-ipc/ssh.config lima-solaris-ipc
```

### Shutting down the VM

```bash
limactl stop solaris-ipc
limactl delete solaris-ipc       # also removes disk image
```

### Running the test suite

`solaris-test.sh` follows the same lifecycle as `freebsd-test.sh`: create VM
if absent, start it, run first-boot setup on the first run, copy source, run
tests, stop the VM on exit.

```bash
./ci/solaris-test.sh [options] [prove options]
```

**Options:**

- `-h`, `--help` — Print usage and exit.

Same prove argument override syntax applies:

```bash
./ci/solaris-test.sh t/15-interval.t
./ci/solaris-test.sh t

VM=my-other-solaris ./ci/solaris-test.sh
```

> **Note:** The first run is slow because it:
>
> 1. Downloads the OmniOS VMDK (~1 GB) and converts it to QCOW2 (one-time;
>    cached at `~/.lima/_cache/omnios-r151058.qcow2` for subsequent runs).
> 2. Boots via QEMU TCG emulation (10-20 min on Apple Silicon).
> 3. Runs `solaris-first-boot.py` via the serial console to create the SSH
>    user, install sudo, and set up the SMF boot-done service.
> 4. Installs `runtime/perl`, GCC, and CPAN dependencies via `pkg` + `cpanm`.
>
> **Unclean shutdown:** The test script avoids unclean shutdowns by issuing
> `sudo shutdown -i5 -g0 -y` via SSH and waiting up to 5 minutes for the VM
> to power off before falling back to `limactl stop`.
>
> Two additional mitigations protect against the case where the VM crashes
> (kernel panic, OOM) and SSH shutdown isn't possible:
>
> - `solaris-first-boot.py` writes `set zfs:zfs_scan_legacy = 0` to
>   `/etc/system`, suppressing the full ZFS device scan that would otherwise
>   run after an unclean shutdown (and take hours under TCG emulation).
> - After every clean shutdown, the test script saves a `qemu-img` snapshot
>   on the VM's QCOW2 disk. On the next start, the snapshot is reverted so
>   that the ZFS pool is never dirty, regardless of how the previous run
>   ended.
>
> If the snapshot or QCOW2 cache becomes corrupted, delete both and let the
> script re-download:
> ```bash
> limactl stop --force solaris-ipc; limactl delete solaris-ipc
> rm -f ~/.lima/_cache/omnios-r151058.qcow2
> ./ci/solaris-test.sh
> ```
>
> If the GCC package name has changed in a newer OmniOS release, adjust the
> `pkg install` line in `solaris-test.sh` (try `pkg search gcc` inside the VM).

---

## Technical Information

Reference for diagnosing and rebuilding VMs. This section covers the
internal mechanics that are not obvious from the scripts alone.

### Lima boot-done mechanism

Lima considers a VM "ready" when a file at a specific path contains the
instance-id that Lima wrote to `cidata.iso` for that start. Lima generates
a **new instance-id on every `limactl start`**, so the boot-done script
inside the VM must read the current id from the cidata ISO — not from a
saved file.

**What Lima checks**: The hostagent SSHes into the VM and runs a boot script
that does `cat /run/lima-boot-done` (note: `/run`, not `/var/run`) and
compares the contents to the expected instance-id. If they don't match,
Lima retries every ~3 seconds for 10 minutes, then gives up with
`did not receive an event with the "running" status`.

**How to read the expected instance-id from the host**:

```python
import subprocess, os
iso = os.path.expanduser("~/.lima/<VM>/cidata.iso")
subprocess.run(["hdiutil", "attach", iso, "-mountpoint", "/tmp/mnt", "-readonly", "-quiet"], check=True)
# Read /tmp/mnt/meta-data, line starting with "instance-id:"
subprocess.run(["hdiutil", "detach", "/tmp/mnt", "-quiet"])
```

**How to check what the VM wrote**:

```bash
ssh -F ~/.lima/<VM>/ssh.config lima-<VM> 'cat /run/lima-boot-done; cat /var/run/lima-boot-done'
```

**How to check what Lima is seeing** (debug log):

```bash
cat ~/.lima/<VM>/ha.stderr.log | tail -20
# Look for the boot-done script trace showing the cat and comparison
```

### Per-OS boot-done implementation

Each OS handles the boot-done marker differently because each has different
init systems and device path conventions.

#### FreeBSD

- **Init**: rc.d service (`/etc/rc.d/lima_boot_done`, enabled via
  `lima_boot_done_enable="YES"` in `/etc/rc.conf`).
- **Cidata device**: `/dev/iso9660/cidata` or `/dev/iso9660/CIDATA`.
- **Mount**: `mount_cd9660 -o ro`.
- **Marker path**: `/var/run/lima-boot-done` (FreeBSD symlinks `/run` →
  `/var/run`, so Lima's check of `/run/lima-boot-done` works).
- **Source**: `freebsd-first-boot.py`, `BOOT_DONE_RC_LINES`.

#### OpenBSD

- **Init**: `/etc/rc.local` snippet (idiomatic OpenBSD one-shot).
- **Cidata device**: `/dev/cd0a` or `/dev/cd1a`.
- **Mount**: `mount_cd9660 -o ro`.
- **Marker path**: `/var/run/lima-boot-done` (OpenBSD symlinks `/run` →
  `/var/run`).
- **Source**: `openbsd-first-boot.py`, `BOOT_DONE_RC_LOCAL`.

#### Linux i386

- **Init**: Lima's standard cloud-init (Linux guest agent handles
  boot-done natively). No custom boot-done script needed.
- **Marker path**: `/run/lima-boot-done` (Linux has `/run` as tmpfs).

#### Solaris / OmniOS CE

- **Init**: SMF transient service (`svc:/site/lima_boot_done:default`).
  Manifest at `/var/svc/manifest/site/lima_boot_done.xml`, method script
  at `/lib/svc/method/lima_boot_done`.
- **Cidata device**: `/dev/dsk/c1t0d0s0` (vioscsi SCSI CD-ROM, slice 0).
  Found via `prtconf -D | grep cdrom` — the device path is
  `/pci@0,0/pci1af4,8@2/iport@iport0/cdrom@0,0`.
- **Mount**: `mount -F hsfs -o ro` (HSFS is the illumos ISO9660 filesystem).
- **Marker path**: Must write to **both** `/var/run/lima-boot-done` AND
  `/run/lima-boot-done`. OmniOS does not have `/run` by default (it is not
  a symlink to `/var/run` like on FreeBSD/OpenBSD), so the method script
  must `mkdir -p /run` and write a second copy there. Lima checks `/run`
  only.
- **Source**: `solaris-first-boot.py`, `BOOT_DONE_METHOD_LINES`.

### Diagnosing a stuck `limactl start`

If `limactl start <VM>` hangs past the SSH phase:

1. **Check if SSH works**:
   ```bash
   ssh -F ~/.lima/<VM>/ssh.config lima-<VM> true && echo OK
   ```
2. **Check the marker**:
   ```bash
   ssh -F ~/.lima/<VM>/ssh.config lima-<VM> 'cat /run/lima-boot-done 2>&1; cat /var/run/lima-boot-done 2>&1'
   ```
3. **Check what Lima expects**:
   ```bash
   # Mount cidata.iso on macOS and read instance-id
   hdiutil attach ~/.lima/<VM>/cidata.iso -mountpoint /tmp/cidata -readonly -quiet
   grep instance-id /tmp/cidata/meta-data
   hdiutil detach /tmp/cidata -quiet
   ```
4. **Check the hostagent debug log**:
   ```bash
   tail -20 ~/.lima/<VM>/ha.stderr.log
   # Look for the [ '' = iid-XXXXXXXXXX ] comparison — empty LHS means
   # the marker file is missing or at the wrong path.
   ```
5. **Fix it live** (while the VM is still running):
   ```bash
   # Write the correct marker so the blocked limactl start completes
   IID=$(hdiutil attach ~/.lima/<VM>/cidata.iso -mountpoint /tmp/cidata -readonly -quiet && grep instance-id /tmp/cidata/meta-data | awk '{print $2}' && hdiutil detach /tmp/cidata -quiet)
   ssh -F ~/.lima/<VM>/ssh.config lima-<VM> "sudo sh -c 'mkdir -p /run; echo $IID > /run/lima-boot-done; echo $IID > /var/run/lima-boot-done'"
   ```

### Crash recovery and QCOW2 snapshots

OpenBSD and Solaris VMs run x86_64 under QEMU TCG emulation on Apple Silicon.
After an unclean shutdown (kernel panic, OOM kill, force-stop), boot-time
filesystem checks that take seconds on bare metal are magnified 10-100x:

- **OpenBSD**: FFS fsck traverses filesystem metadata. Under TCG this can
  take tens of minutes.
- **Solaris/OmniOS**: ZFS performs a full pool device scan. Under TCG this
  can take **hours**.

The test scripts for these VMs use a QCOW2 snapshot strategy to avoid ever
booting a dirty filesystem:

**How it works:**

1. On shutdown, the script SSHs into the VM and issues a clean OS-level
   shutdown (`doas shutdown -h now` for OpenBSD, `sudo shutdown -i5 -g0 -y`
   for Solaris). It polls until the VM powers off.
2. If the VM stops cleanly, `qemu-img snapshot -c clean` saves a named
   snapshot on `~/.lima/<VM>/disk`. The snapshot captures the filesystem in
   a clean (fsck'd / ZFS-exported) state.
3. On the next `limactl start`, the script runs `qemu-img snapshot -a clean`
   to revert to the last clean snapshot before booting. The filesystem is
   never marked dirty, so fsck and ZFS scans never run.
4. If the VM crashed and the script had to force-stop, no snapshot is saved —
   the previous clean snapshot is reverted on the next start instead.

This means that even after a hard crash, the VM boots from the last
known-clean state. The only cost is that any filesystem changes made during
the crashed run (test output, core dumps, package installs) are discarded.
Since the scripts re-copy the source tree and re-install packages idempotently
on every run, this is harmless.

**First-boot snapshot:**

After `*-first-boot.py` completes successfully, the test script takes an
initial snapshot. The first-boot script halts the VM cleanly (via the guest
OS's own shutdown), so the filesystem is already clean.

**Manual snapshot management:**

```bash
# List snapshots
qemu-img snapshot -l ~/.lima/openbsd-ipc/disk

# Revert to a snapshot (VM must be stopped)
qemu-img snapshot -a clean ~/.lima/openbsd-ipc/disk

# Delete a snapshot
qemu-img snapshot -d clean ~/.lima/openbsd-ipc/disk
```

**Additional Solaris mitigation:**

Beyond snapshots, `solaris-first-boot.py` writes `set zfs:zfs_scan_legacy = 0`
to `/etc/system` inside the VM. This kernel parameter disables the legacy ZFS
pool scan at import time, so even if the VM boots a dirty pool (e.g. before
the first snapshot exists), ZFS won't spend hours scanning. This parameter
takes effect on the next boot after first-boot completes.

### Rebuilding a VM from scratch

If a VM's disk is corrupted or you need a clean slate:

```bash
limactl stop --force <VM> 2>/dev/null
limactl delete <VM>
# For OpenBSD and Solaris, also delete the first-boot sentinel if it exists:
rm -f ~/.lima/<VM>/.first-boot-done
# Then run the test script — it will recreate and provision automatically:
./ci/<os>-test.sh
```

For Solaris specifically, if the QCOW2 cache is corrupted (e.g. after a
force-kill during boot that left ZFS dirty):

```bash
rm -f ~/.lima/_cache/omnios-r151058.qcow2
# The test script will re-download and re-convert from the VMDK.
```

### Expected boot times (Apple Silicon, M-series)

| VM          | Arch    | Emulation | Boot → SSH | Boot → Ready |
|-------------|---------|-----------|------------|--------------|
| freebsd-ipc | aarch64 | Native    | ~6s        | ~7s          |
| linux-i386  | x86_64  | TCG       | ~24s       | ~29s         |
| openbsd-ipc | x86_64  | TCG       | ~32s       | ~33s         |
| solaris-ipc | x86_64  | TCG       | ~56s       | ~58s         |

FreeBSD is fastest because it runs natively on Apple Silicon (aarch64,
hardware virtualisation). The other three use QEMU TCG (software x86_64
emulation). Solaris is slowest due to the illumos boot sequence (SMF
dependency resolution, ZFS pool import).

### Solaris-specific quirks

- **No `/run` directory.** OmniOS uses `/var/run` exclusively. Any script
  that writes a marker, PID file, or socket to `/run` must also create the
  directory and write a copy there if Lima or another tool expects it.
- **HSFS for ISO9660.** Use `mount -F hsfs`, not `mount -t iso9660`.
- **Shutdown must use `shutdown -i5 -g0 -y`**, not `poweroff` or `halt`.
  The ACPI powerdown (`limactl stop`) also works but is slower under TCG.
  Always prefer the SSH shutdown path to ensure ZFS gets a clean export.
- **`pkg install` is idempotent** — already-installed packages are skipped.
  GCC is currently `developer/gcc14`; if OmniOS bumps the version, use
  `pkg search gcc` inside the VM to find the new package name.
- **`cpanm` may land outside `$PATH`** on OmniOS. The test script searches
  `/usr/perl5` and `/opt` for the binary and symlinks it to `/usr/bin/cpanm`.
- **`gmake` required for CPAN XS builds.** OmniOS's `/usr/bin/make` is not
  GNU make. Pass `MAKE=gmake` to `cpanm` or `perl Makefile.PL`.
