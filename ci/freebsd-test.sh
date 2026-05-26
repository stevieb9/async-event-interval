#!/bin/sh
# Run Async::Event::Interval tests in a local FreeBSD VM (Lima template).
# Usage: ./ci/freebsd-test.sh [--perl-version <ver>] [prove options]

set -e

VM="${VM:-freebsd-ipc}"
HOST_REPO="$(cd "$(dirname "$0")/.." && pwd)"
GUEST_USER="freebsd"
GUEST_HOME="/home/${GUEST_USER}.guest"
GUEST_REPO="${GUEST_HOME}/async-event-interval"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PERL_VERSION=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [prove options]

Options:
  --perl-version <ver>  Build and test with perlbrew Perl <ver> (e.g. 5.20.3).
                        Compiles Perl from source on the first run (10-20 min);
                        subsequent runs reuse the cached build.
  -h, --help            Show this help message and exit

Environment:
  VM=<name>       Target a different Lima VM (default: freebsd-ipc)

Prove options default to "-v t" (verbose, full suite) when not supplied.
Examples:
  $(basename "$0")                              # full suite
  $(basename "$0") --perl-version 5.20.3        # full suite, Perl 5.20.3
  $(basename "$0") t/15-interval.t              # single test file
  $(basename "$0") t                            # full suite, no -v
EOF
}

_PROVE_ARGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --perl-version) shift; PERL_VERSION="$1"; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              _PROVE_ARGS="${_PROVE_ARGS} $1"; shift ;;
    esac
done
PROVE_ARGS="${_PROVE_ARGS# }"
PROVE_ARGS="${PROVE_ARGS:--v t}"

cleanup() {
    status=$?
    echo "==> Stopping VM '${VM}'..."
    limactl stop "$VM" >/dev/null 2>&1 || true
    trap - EXIT INT TERM
    exit "$status"
}

trap cleanup EXIT INT TERM

if ! limactl list 2>/dev/null | awk '{print $1}' | grep -qx "$VM"; then
    echo "==> Creating VM '${VM}' from Lima template..."
    limactl create --name "$VM" --tty=false "${SCRIPT_DIR}/freebsd-lima.yaml"
fi

if ! limactl list | grep -q "^${VM}[[:space:]].*Running"; then
    echo "==> Starting VM '${VM}'..."
    limactl start "$VM" &
    _LIMA_PID=$!

    # Lima's generated cloud-init YAML uses 1-space list indentation which
    # FreeBSD's flua YAML parser rejects.  On a fresh VM this means the
    # 'freebsd' SSH user and the boot-done marker are never created, and
    # 'limactl start' hangs indefinitely.  Poll for SSH; if it isn't
    # available after 60 s, run freebsd-first-boot.py via the serial console
    # to set up the user, install a persistent boot-done rc.d service, and
    # write the marker for this boot.  Subsequent starts will be fast.
    _SSH_OK=0
    for _I in $(seq 1 20); do
        if ssh -F ~/.lima/"$VM"/ssh.config lima-"$VM" true 2>/dev/null; then
            _SSH_OK=1; break
        fi
        sleep 3
    done

    if [ "$_SSH_OK" = "0" ]; then
        echo "==> SSH unavailable – running first-boot setup (one-time)..."
        python3 "${SCRIPT_DIR}/freebsd-first-boot.py" "$VM"
    fi

    # Wait for Lima to finish its startup sequence (should complete now that
    # SSH works and the boot-done marker exists).
    wait "$_LIMA_PID" || true

    limactl list | grep -q "^${VM}[[:space:]].*Running" || {
        echo "ERROR: VM '${VM}' is not Running after start"; exit 1; }
fi

# Suppress FreeBSD daily tips (fortune freebsd-tips in .profile/.login).
ssh -F ~/.lima/"$VM"/ssh.config lima-"$VM" \
    'sed -i "" -e "/fortune freebsd-tips/s/^/#/" ~/.profile ~/.login' \
    2>/dev/null || true

# If sudo is missing (VM was set up before the first-boot script included the
# pkg install step), run first-boot again while the VM is still running so the
# serial console socket is available.
if ! limactl shell "$VM" -- sh -lc 'command -v sudo >/dev/null 2>&1'; then
    echo "==> sudo not found – running first-boot setup to install it..."
    python3 "${SCRIPT_DIR}/freebsd-first-boot.py" "$VM"
fi

echo "==> Installing FreeBSD packages..."
limactl shell "$VM" -- sh -lc '
    sudo pkg install -y perl5 p5-App-cpanminus gmake p5-ExtUtils-MakeMaker \
        p5-Test-SharedFork p5-Mock-Sub p5-Parallel-ForkManager
    # IPC::Shareable: the p5-IPC-Shareable pkg is pinned at 1.13 but
    # Async::Event::Interval requires >= 1.14, so always cpanm --reinstall
    # to pull the latest from CPAN.  --notest skips its slow SysV-IPC test
    # suite; we want the module, not its self-tests.
    sudo cpanm --reinstall --notest IPC::Shareable
'

if [ -n "$PERL_VERSION" ]; then
    echo "==> Setting up Perl ${PERL_VERSION} via perlbrew (compiles from source on first run)..."
    limactl shell "$VM" -- sh -lc "
        set -e
        sudo pkg install -y gcc gmake curl

        if [ ! -x \"\$HOME/perl5/perlbrew/bin/perlbrew\" ]; then
            # Install system-wide so App::perlbrew is in the system perl @INC.
            # Avoids the curl|bash installer (requires bash, external URL).
            sudo cpanm --notest App::perlbrew
            # init creates the directory skeleton but does not place the binary;
            # copy it from where cpanm installed it to the expected stable path.
            perlbrew init
            cp \"\$(command -v perlbrew)\" \"\$HOME/perl5/perlbrew/bin/perlbrew\"
        fi

        PERLBREW=\"\$HOME/perl5/perlbrew/bin/perlbrew\"

        if ! \"\$PERLBREW\" list | grep -qF '${PERL_VERSION}'; then
            echo '==> Compiling perl-${PERL_VERSION} — this takes 10-20 minutes...'
            \"\$PERLBREW\" install perl-${PERL_VERSION} --notest -j 2
        fi

        PERL_BIN=\"\$HOME/perl5/perlbrew/perls/perl-${PERL_VERSION}/bin\"

        if [ ! -x \"\$PERL_BIN/cpanm\" ]; then
            curl -fsSL https://cpanmin.us -o /tmp/_cpanm_bootstrap.pl
            \"\$PERL_BIN/perl\" /tmp/_cpanm_bootstrap.pl App::cpanminus
            rm -f /tmp/_cpanm_bootstrap.pl
        fi

        \"\$PERL_BIN/cpanm\" --notest Test::SharedFork Mock::Sub \\
            Parallel::ForkManager
        # IPC::Shareable: always pull the latest (see main install step).
        \"\$PERL_BIN/cpanm\" --reinstall --notest IPC::Shareable
    "
fi

echo "==> Cleaning up stale IPC segments/semaphores from previous runs..."
limactl shell "$VM" -- sh -lc "
    for id in \$(ipcs -m 2>/dev/null | awk '/${GUEST_USER}/ {print \$2}'); do
        ipcrm -m \$id 2>/dev/null || true
    done
    for id in \$(ipcs -s 2>/dev/null | awk '/${GUEST_USER}/ {print \$2}'); do
        ipcrm -s \$id 2>/dev/null || true
    done
" || true

echo "==> Copying source into VM..."
limactl shell "$VM" -- sh -lc "rm -rf '${GUEST_REPO}'"
scp -F ~/.lima/"$VM"/ssh.config -r "$HOST_REPO" "lima-${VM}:${GUEST_HOME}/"
# Strip macOS resource-fork files (._*).
limactl shell "$VM" -- sh -lc "find '${GUEST_REPO}' -name '._*' -delete" 2>/dev/null || true

_test_rc=0
if [ -n "$PERL_VERSION" ]; then
    echo "==> Running tests in VM with Perl ${PERL_VERSION}..."
    limactl shell "$VM" -- sh -lc "
        PERL_BIN=\"\$HOME/perl5/perlbrew/perls/perl-${PERL_VERSION}/bin\"
        cd '${GUEST_REPO}' && PATH=\"\$PERL_BIN:\$PATH\" PERL5LIB=lib prove -l ${PROVE_ARGS}
    " || _test_rc=$?
else
    echo "==> Running tests in VM..."
    limactl shell "$VM" -- sh -lc "cd '${GUEST_REPO}' && PERL5LIB=lib prove -l ${PROVE_ARGS}" \
        || _test_rc=$?
fi

echo "==> Async::Event::Interval version tested..."
limactl shell "$VM" -- sh -lc "cd '${GUEST_REPO}' && perl -Ilib -MAsync::Event::Interval -e 'print qq(Async::Event::Interval \$Async::Event::Interval::VERSION\n)'"
echo "==> IPC::Shareable version tested..."
limactl shell "$VM" -- sh -lc "cd '${GUEST_REPO}' && perl -Ilib -MIPC::Shareable -e 'print qq(IPC::Shareable \$IPC::Shareable::VERSION\n)'"

echo "==> VM environment info..."
limactl shell "$VM" -- sh -lc "uname -a; perl -v | head -2; perl -V:archname"

exit $_test_rc
