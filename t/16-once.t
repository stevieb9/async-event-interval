use strict;
use warnings;

use IPC::Shareable;
use Test::More;
use Time::HiRes qw(usleep);

my ($segs_before, $sems_before);
BEGIN {
    $segs_before = IPC::Shareable::seg_count();
    $sems_before = IPC::Shareable::sem_count();
}

use Async::Event::Interval;

warn "Segs Before: $segs_before\n" if $ENV{PRINT_SEGS};
warn "Sems Before: $sems_before\n" if $ENV{PRINT_SEGS};

my $mod = 'Async::Event::Interval';

{
    my $e = $mod->new(0, sub {select(undef, undef, undef, 0.5)});

    is $e->waiting, 1, "Before start, the event is waiting";

    $e->start;

    sleep 1;

    is $e->status, 0, "Zero as interval sets status to complete (0)";
    is $e->error, 1, "Zero as interval sets error to true";
    is $e->_pid, -99, "Zero as interval sets _pid to -99";
    is $e->waiting, 1, "Zero as interval sets waiting to true";

    $e->start;
    is $e->waiting, 0, "An event doesn't set waiting until after it's done";

    sleep 1;

    is $e->waiting, 1, "Event sets waiting after it completes";
}

Async::Event::Interval::_end();
IPC::Shareable::_end;

my $segs_after = IPC::Shareable::seg_count();
my $sems_after = IPC::Shareable::sem_count();
warn "Segs After: $segs_after\n" if $ENV{PRINT_SEGS};
warn "Sems After: $sems_after\n" if $ENV{PRINT_SEGS};

is $segs_after, $segs_before, "All segs cleaned up ok";
is $sems_after, $sems_before, "All semaphore sets cleaned up ok";

done_testing();