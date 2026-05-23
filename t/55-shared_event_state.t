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

my $mod = 'Async::Event::Interval';

# runs()
{
    my $e = $mod->new(0.1, sub {});

    $e->start;
    select(undef, undef, undef, 0.7);
    $e->stop;

    my $method_runs = $e->runs;
    my $info_runs = $e->info->{runs};

    is $method_runs, $info_runs, "run() returns same data for runs as info()";
    is $method_runs > 5, 1, "Number of runs appears to be correct";

    my $event_runs = $e->events->{$e->id}{runs};
    is $method_runs, $event_runs, "events(id) returns same data as runs() ok";
}

# errors()
{
    my $e = $mod->new(0.1, sub { die("some failure"); });

    $e->start;
    select(undef, undef, undef, 0.3);
    $e->stop;

    is $e->errors, 1, "errors() shared data ok";

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