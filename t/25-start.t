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

    { # warn on start() if started

        my $w;
        local $SIG{__WARN__} = sub { $w = shift };
        $e->start;
        $e->start;
        $e->stop;

        like $w, qr/already running/, "start() if called after started warns";
    }
    { # warn on restart() if started

        my $w;
        local $SIG{__WARN__} = sub { $w = shift };

        is $w, undef, "the warning is clear";
        $e->start;
        $e->restart;
        $e->stop;

        like $w, qr/already running/, "restart() if called after started warns";
    }
}

sub perform {
    return;
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