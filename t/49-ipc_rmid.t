use strict;
use warnings;

use lib 't/lib';
use TestHelper;
use Test::More;

# Test that the IPC_RMID-at-creation fix is properly integrated.
#
# _mark_events_seg_for_destroy() is called from _create_events_seg()
# which runs at module load. Verify that:
#
#   1. The function exists
#   2. After module load, %events is fully functional (read/write/lock)
#   3. Events survive create/destroy cycles across the same %events segment
#
# On non-Darwin platforms, the function sets shmctl(IPC_RMID) /
# semctl(IPC_RMID) after the tie, making the segment crash-safe.
# On Darwin, the function is a no-op (macOS destroys segment contents
# on IPC_RMID).

use Async::Event::Interval;

# 1. The function exists
ok(
    Async::Event::Interval->can('_mark_events_seg_for_destroy'),
    '_mark_events_seg_for_destroy is callable'
);

# 2. %events is functional after module load — create and read an event
{
    my $e = Async::Event::Interval->new(5, sub {});
    isa_ok($e, 'Async::Event::Interval');

    my $id = $e->id;
    ok(defined $id, "event got an id ($id)");

    my $info = $e->info;
    is($info->{interval}, 5, 'event interval stored in %events');

    # Event goes out of scope → DESTROY → removed from %events
}

# 3. Multiple events in sequence (exercise repeated read/write to %events)
{
    for my $i (1 .. 3) {
        my $e = Async::Event::Interval->new($i, sub {});
        is($e->interval, $i, "event $i interval round-trips through %events");
    }
}

# 4. Rapid create/destroy with interleaved IDs
{
    my $e0 = Async::Event::Interval->new(0.5, sub {});
    my $e1 = Async::Event::Interval->new(0.5, sub {});
    my $id0 = $e0->id;
    my $id1 = $e1->id;
    ok($id0 != $id1, "sequential events get distinct IDs ($id0, $id1)");
}