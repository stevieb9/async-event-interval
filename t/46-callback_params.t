use warnings;
use strict;

use IPC::Shareable;
use Test::More;
use Test::SharedFork;

my ($segs_before, $sems_before);
BEGIN {
    $segs_before = IPC::Shareable::seg_count();
    $sems_before = IPC::Shareable::sem_count();
}

use Async::Event::Interval;

warn "Segs Before: $segs_before\n" if $ENV{PRINT_SEGS};
warn "Sems Before: $sems_before\n" if $ENV{PRINT_SEGS};

my @params = (
    { 0 => 'a' },
    { 1 => 'b' },
    { 2 => 'c' },
);

my $event = Async::Event::Interval->new(
    0,
    \&callback
);

for (0..2) {
    $event->start($_, $params[$_]);
    while (! $event->waiting) {}
}

$event->stop;

Async::Event::Interval::_end();
IPC::Shareable::_end;

my $segs_after = IPC::Shareable::seg_count();
my $sems_after = IPC::Shareable::sem_count();
warn "Segs After: $segs_after\n" if $ENV{PRINT_SEGS};
warn "Sems After: $sems_after\n" if $ENV{PRINT_SEGS};

is $segs_after, $segs_before, "All segs cleaned up ok";
is $sems_after, $sems_before, "All semaphore sets cleaned up ok";

done_testing();

sub callback {
    my ($iter, $href) = @_;

    if ($iter == 0) {
        is $href->{$iter}, 'a', "start() param on iter $iter ok";
    }
    elsif ($iter == 1) {
        is $href->{$iter}, 'b', "start() param on iter $iter ok";
    }
    elsif ($iter == 2) {
        is $href->{$iter}, 'c', "start() param on iter $iter ok";
    }
}