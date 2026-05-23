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

{
    my $e = $mod->new(1, \&perform, 10);

    $e->start;
    is $e->status > 0, 1, "started ok";
    is $e->error, 0, "no error ok";

    sleep 3;

    is $e->status, 0, "after a crash, status returns 0";
    is $e->error, 1, "after a crash, error returns 1";

    $e->restart;

    is $e->status > 0, 1, "restarted ok";
    is $e->error, 0, "no error ok";

    sleep 3;

    is $e->status, 0, "after a crash, status returns 0";
    is $e->error, 1, "after a crash, error returns 1";
}

sub perform {
    local $SIG{ALRM} = sub { kill 9, $$; };
    alarm 1;
    sleep 2;
    alarm 0;
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