use strict;
use warnings;

use IPC::Shareable;
use Test::More;

my ($segs_before, $sems_before);
BEGIN {
    $segs_before = IPC::Shareable::seg_count();
    $sems_before = IPC::Shareable::sem_count();
}

use Async::Event::Interval;

warn "Segs Before: $segs_before\n" if $ENV{PRINT_SEGS};
warn "Sems Before: $sems_before\n" if $ENV{PRINT_SEGS};

{
    my $event = Async::Event::Interval->new(
        0.3,
        sub {
            kill 9, $$;
        },
    );

    $event->start;

    is $event->status > 0, 1, "status ok at start";

    select(undef, undef, undef, 0.6);

    is $event->status, 0, "upon crash, status return ok";
    is $event->error, 1, "upon crash, error return ok";

    if ($event->error){
        $event->restart;
        is $event->status > 0, 1, "after restart, status ok again";
        is $event->error, 0, "...so is error";
    }

    $event->stop;
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