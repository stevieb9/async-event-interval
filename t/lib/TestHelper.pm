package TestHelper;

use strict;
use warnings;

use IPC::Shareable;
use Test::More;

our $TESTING_DIST = 'Async::Event::Interval';

my ($segs_before, $sems_before);
my $parent_pid;
my $installed;

sub import {
    return if $installed;
    $installed = 1;
    $parent_pid = $$;

    IPC::Shareable->testing_set($TESTING_DIST);

    $segs_before = IPC::Shareable::seg_count();
    $sems_before = IPC::Shareable::sem_count();

    warn "Segs Before: $segs_before\n" if $ENV{PRINT_SEGS};
    warn "Sems Before: $sems_before\n" if $ENV{PRINT_SEGS};
}

END {
    return unless $installed;
    return if $$ != $parent_pid;

    $SIG{CHLD} = 'DEFAULT';
    $? = 0;

    eval { Async::Event::Interval::_end() }
        if Async::Event::Interval->can('_end');
    eval { IPC::Shareable::_end() };

    eval { IPC::Shareable::clean_up_testing($TESTING_DIST) };

    my $segs_after = IPC::Shareable::seg_count();
    my $sems_after = IPC::Shareable::sem_count();

    warn "Segs After: $segs_after\n" if $ENV{PRINT_SEGS};
    warn "Sems After: $sems_after\n" if $ENV{PRINT_SEGS};

    is $segs_after, $segs_before, "All segs cleaned up ok";
    is $sems_after, $sems_before, "All semaphore sets cleaned up ok";

    done_testing();
}

1;
