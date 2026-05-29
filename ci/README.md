# CI VM Tests

Thin wrappers that delegate to the shared CI scripts in the `ipc-shareable`
repository. All VM definitions, first-boot setup, and test logic live there.

## Usage

```sh
# Run all VMs
./ci/vm-tests.sh

# FreeBSD only, single test file
./ci/freebsd-test.sh t/15-interval.t

# Linux i386 only, verbose
./ci/linux-i386-test.sh -v t/15-interval.t

# OpenBSD only
./ci/openbsd-test.sh

# Solaris/OmniOS only
./ci/solaris-test.sh

# FreeBSD + Linux only, keep logs
./ci/vm-tests.sh -f -l -k

# Stream output to stdout instead of log files
./ci/vm-tests.sh -D
```

Each wrapper passes `--project async-event-interval` automatically, so you
never need to type `-p` or `--project` from this repo. All flags listed in
the shared scripts' `--help` are forwarded as-is.

## vm-tests.sh flags

| Flag | Description |
|---|---|
| `-f`, `--freebsd` | FreeBSD only |
| `-l`, `--linux` | 32-bit Linux (i386) only |
| `-o`, `--openbsd` | OpenBSD only |
| `-s`, `--solaris` | Solaris/OmniOS only |
| `-d`, `--dragonfly` | DragonFly BSD only |
| `-a`, `--all` | All VMs (default) |
| `-k`, `--keep-logs` | Keep log files after run |
| `-D`, `--display` | Write output to stdout (no log files) |

Prove options (`-v`, test file paths, etc.) are forwarded to each VM's test
invocation. Default prove args: `-v t`.

## Environment

```
VM=my-custom-vm ./ci/freebsd-test.sh
IPC_DEBUG_DELTAS=1 ./ci/freebsd-test.sh   # per-file IPC leak detection
```

`IPC_DEBUG_DELTAS=1` snapshots `ipcs -s` / `ipcs -m` counts before and
after each `.t` file and emits an `IPC-DELTA LEAK:` line on stderr for any
file with a net-positive delta. Off by default; use when investigating a
suspected per-file leak.

## Platform-adaptive tests

`t/68-shared_scalar_complex.t` allocates many shared scalars with nested
structures and can exceed the kernel's `semmni` (max semaphore identifier
sets) on tight platforms. It probes available headroom at startup and
branches:

| Headroom (sets) | Behavior |
|---|---|
| `>= 65` or unknown | Full battery: all 18 subtests |
| `>= 45` | Reduced: skips subtests 4, 8, 9, 12, 13 (the heaviest) |
| `< 45` | `plan skip_all` with a remediation diag |

Typical platform headrooms: macOS 87000+, Linux 32000, FreeBSD default 49,
OpenBSD default 9. Raise the kernel limit (`kern.ipc.semmni` on FreeBSD,
`/proc/sys/kernel/sem` field 4 on Linux) to enable the full battery on
tight platforms.

## Output

Each per-VM script prints a summary after tests complete:

```
==> Project: async-event-interval
==> Tested: Async::Event::Interval 1.20
==> IPC::Shareable installed: 1.16
==> VM: freebsd-ipc
==> OS Version: FreeBSD 14.3-RELEASE ...
==> Perl version: 5.42.0
==> Mode: pure Perl
```

When run via `vm-tests.sh`, a results table prints after all VMs finish,
with per-VM PASS/FAIL status and failed test details.

## How it works

```
async-event-interval/ci/freebsd-test.sh
  → ipc-shareable/ci/freebsd-test.sh --project async-event-interval
```

The shared script handles VM lifecycle (create/start), dependency
installation, source copy, IPC cleanup, test execution, and VM stop. The
`--project` flag selects the right guest repo path, CPAN dependencies, and
test invocation for this project.

Full documentation of available options, VM configuration, and
troubleshooting: `../ipc-shareable/ci/README.md`.
