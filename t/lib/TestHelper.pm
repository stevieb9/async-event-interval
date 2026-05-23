package TestHelper;

use strict;
use warnings;

use IPC::Shareable;
use Test::More;

# Test helper: capture the seg/sem baseline at import time, then in an
# END block run AEI/IPC::Shareable cleanup, assert the counts returned
# to the baseline, and call done_testing for the caller.
#
# Usage:
#
#     use strict;
#     use warnings;
#     use lib 't/lib';
#     use TestHelper;                  # capture baseline (must come BEFORE
#                                      # `use Async::Event::Interval;`)
#     use Test::More;
#     use Async::Event::Interval;
#
#     # ... tests, with event objects scoped in { } blocks so they
#     # DESTROY before this file ends ...
#
#     # NOTE: do NOT call done_testing(). TestHelper's END block calls
#     # it for you after the leak assertions have run.
#
# Set PRINT_SEGS=1 in the environment to dump the before/after counts.

my ($segs_before, $sems_before);
my $parent_pid;
my $installed;

sub import {
    return if $installed;
    $installed = 1;
    $parent_pid = $$;

    $segs_before = IPC::Shareable::seg_count();
    $sems_before = IPC::Shareable::sem_count();

    warn "Segs Before: $segs_before\n" if $ENV{PRINT_SEGS};
    warn "Sems Before: $sems_before\n" if $ENV{PRINT_SEGS};
}

END {
    return unless $installed;

    # AEI events run in a forked child via Parallel::ForkManager, and
    # those children inherit this END block. We must not emit test
    # assertions, do cleanup, or call done_testing() from inside the
    # child — the parent's Test::Builder state isn't accessible there
    # and the child's exit would corrupt the parent's TAP/exit code.

    return if $$ != $parent_pid;

    # AEI sets $SIG{CHLD} = 'IGNORE' at module load so children are
    # auto-reaped. Perl/Test2 waitpid returns -1 with CHLD ignored, which
    # can corrupt the test exit code. Restore DEFAULT before exit.

    $SIG{CHLD} = 'DEFAULT';
    $? = 0;

    # Drop the AEI %events protected segment (if AEI is loaded and
    # `%events` is empty) and any destroy=>1 segments this process
    # owns. We do this explicitly rather than relying on the natural
    # LIFO ordering of the END blocks shipped by AEI and IPC::Shareable.

    eval { Async::Event::Interval::_end() }
        if Async::Event::Interval->can('_end');
    eval { IPC::Shareable::_end() };

    my $segs_after = IPC::Shareable::seg_count();
    my $sems_after = IPC::Shareable::sem_count();

    warn "Segs After: $segs_after\n" if $ENV{PRINT_SEGS};
    warn "Sems After: $sems_after\n" if $ENV{PRINT_SEGS};

    is $segs_after, $segs_before, "All segs cleaned up ok";
    is $sems_after, $sems_before, "All semaphore sets cleaned up ok";

    done_testing();
}

1;