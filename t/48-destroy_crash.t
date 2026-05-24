use strict;
use warnings;

use lib 't/lib';
use TestHelper;
use Test::More;

use FindBin;
use IPC::Shareable;
use File::Temp qw(tempfile);

# IPC::Shareable::seg_count() and sem_count() shell out to ipcs(1)
# for a global view. Skip if ipcs is unavailable.
my $ipcs_available = system('which ipcs >/dev/null 2>&1') == 0;
my $ipcrm_available = system('which ipcrm >/dev/null 2>&1') == 0;

if (! $ipcs_available || ! $ipcrm_available) {
    plan skip_all => "ipcs and ipcrm required";
}

# The test process has already loaded Async::Event::Interval (via
# TestHelper), so %events is tied in the parent and contributes to
# the global seg/sem count. Record "after parent load" baseline.

my $segs_parent = IPC::Shareable::seg_count();
my $sems_parent = IPC::Shareable::sem_count();

diag("Parent baseline: $segs_parent segs, $sems_parent sems");

# Snapshot all current SHM and semaphore IDs so we can identify the
# child's ones after the crash. Filter to only data lines.
my %shm_before = map { (split)[1] => 1 } grep { /^\s*m\s+\d+/ } `ipcs -m 2>/dev/null`;
my %sem_before = map { (split)[1] => 1 } grep { /^\s*s\s+\d+/ } `ipcs -s 2>/dev/null`;

# Fork a child that execs a fresh Perl loading AEI independently.
# The child must load our locally modified AEI (not a system-installed
# copy), so pass -I with the lib path.
my ($sync_fh, $sync_tmp) = tempfile(UNLINK => 1);
my $lib_dir = "$FindBin::Bin/../lib";

my ($script_fh, $script_tmp) = tempfile(UNLINK => 1);
print $script_fh <<"    EOSCRIPT";
        use lib '$lib_dir';
        use Async::Event::Interval;      # _create_events_seg() runs at load time
    EOSCRIPT
print $script_fh qq{
        open my \$fh, '>', '$sync_tmp' or die \$!;
        print \$fh "READY\\n";
        close \$fh;
        sleep 30;
};
close $script_fh;

my $child_pid = fork();
if (! defined $child_pid) {
    die "fork() failed: $!";
}

if (! $child_pid) {
    exec $^X, $script_tmp;
    die "exec failed: $!";
}

# Parent: poll the sync file until child signals ready.
{
    my $waited = 0;
    my $ok;
    while ($waited < 10) {
        if (-s $sync_tmp) {
            open my $in, '<', $sync_tmp;
            chomp(my $line = <$in>);
            close $in;
            if ($line && $line eq 'READY') {
                $ok = 1;
                last;
            }
        }
        select(undef, undef, undef, 0.1);
        $waited += 0.1;
    }
    if (! $ok) {
        kill 'KILL', $child_pid;
        waitpid $child_pid, 0;
        BAIL_OUT("Child did not signal ready within 10s");
    }
}

select(undef, undef, undef, 0.3);

my $segs_before_kill = IPC::Shareable::seg_count();
my $sems_before_kill = IPC::Shareable::sem_count();

# Kill the child with SIGKILL — uncatchable, END/DESTROY never run.
kill 'KILL', $child_pid;
waitpid $child_pid, 0;

select(undef, undef, undef, 0.2);

my $segs_after = IPC::Shareable::seg_count();
my $sems_after = IPC::Shareable::sem_count();

diag("Before kill: $segs_before_kill segs, $sems_before_kill sems");
diag("After kill:  $segs_after segs, $sems_after sems");

# With the IPC_RMID-at-creation fix, the child's segment and semaphore
# are marked for destruction at tie time. When SIGKILL kills the child
# (the only attached process), the kernel auto-frees both resources.
#
# On macOS, shmctl(IPC_RMID) immediately destroys segment contents (reads
# return empty, writes write nothing), so the fix is disabled on Darwin.
# The leak persists on macOS; the END-block cleanup path handles normal
# exit but cannot catch SIGKILL.

my $seg_diff = $segs_after - $segs_parent;
my $sem_diff = $sems_after - $sems_parent;

SKIP: {
    skip 'IPC_RMID fix disabled on Darwin (destroys segment contents)', 2
        if $^O eq 'darwin';

    is $seg_diff, 0,
        "No SHM leak after SIGKILL (diff=$seg_diff, parent=$segs_parent)";
    is $sem_diff, 0,
        "No semaphore leak after SIGKILL (diff=$sem_diff, parent=$sems_parent)";
}

# Clean up: find any IDs that appeared after the baseline snapshot and
# remove them with ipcrm (backstop in case of unexpected leakage).
{
    my %shm_after = map { (split)[1] => 1 } grep { /^\s*m\s+\d+/ } `ipcs -m 2>/dev/null`;
    my %sem_after = map { (split)[1] => 1 } grep { /^\s*s\s+\d+/ } `ipcs -s 2>/dev/null`;

    my $removed_shm = 0;
    for my $id (keys %shm_after) {
        next if $shm_before{$id};
        system('ipcrm', '-m', $id) == 0 and $removed_shm++;
    }

    my $removed_sem = 0;
    for my $id (keys %sem_after) {
        next if $sem_before{$id};
        system('ipcrm', '-s', $id) == 0 and $removed_sem++;
    }

    diag("Removed $removed_shm shm, $removed_sem sem via ipcrm");
}

# Give the OS a moment to process any removals
select(undef, undef, undef, 0.3);

# Verify cleanup restored counts to parent baseline.
{
    my $segs_final = IPC::Shareable::seg_count();
    my $sems_final = IPC::Shareable::sem_count();

    is $segs_final, $segs_parent,
        "Seg count back to parent baseline ($segs_final == $segs_parent)";

    is $sems_final, $sems_parent,
        "Sem count back to parent baseline ($sems_final == $sems_parent)";
}

ok 1, "Crash-leak fix verification complete";
