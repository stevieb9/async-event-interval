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
    my $e = $mod->new(0.5, \&perform);
    my $x = $mod->new(0, \&multi);

    my $scalar_a = $e->shared_scalar;
    my $scalar_b = $e->shared_scalar;

    is ref $scalar_a, 'SCALAR', "shared var a is a scalar when initialized" ;
    is ref $scalar_b, 'SCALAR', "shared var b is a scalar when initialized" ;

    $$scalar_a = -1;
    is $$scalar_a, -1, "shared var a has original value -1 before event start" ;
    $$scalar_b = -2;
    is $$scalar_b, -2, "shared var b has original value -2 before event start" ;

    $e->start;
    sleep 1;
    $e->stop;

    is $$scalar_a, 99, "shared var a has updated value after event start" ;
    is $$scalar_b, 98, "shared var b has updated value after event start" ;

    $x->start;
    sleep 1;
    $x->stop;

    is $$scalar_a, 'hello, world', "shared var a has updated value in separate event" ;

    sub perform {
        $$scalar_a = 99;
        $$scalar_b = 98;
    }

    sub multi {
        $$scalar_a = 'hello, world';
    }
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