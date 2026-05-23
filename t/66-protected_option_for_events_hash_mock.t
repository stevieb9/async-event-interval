use strict;
use warnings;

use IPC::Shareable;
use Mock::Sub;
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

# No call to IPC::Shareable::clean_up_protected()
{
    my ($keys, $register, $protect_lock, $sub);
    my $m = Mock::Sub->new;

    {
        $register = IPC::Shareable::global_register;
        $keys = keys %$register;
        is $keys, 1, "IPC::Shareable shows one entry before event creation ok";

        my $e = $mod->new(0, sub {});
        $protect_lock = $e->_shm_lock;

        $register = IPC::Shareable::global_register;
        $keys = keys %$register;
        is $keys, 2, "IPC::Shareable shows two entries after event creation ok";

        $sub = $m->mock('Async::Event::Interval::_shm_lock');
        $sub->return_value(999999);

        is $e->_shm_lock, 999999, "Mock::Sub has properly mocked _shm_lock()";
    }

    $register = IPC::Shareable::global_register;
    $keys = keys %$register;
    is $keys, 2, "The \%events hash shm segment nor its child wasn't removed ok";

    $sub->unmock;

    # Force the END block for cleanup
    Async::Event::Interval::_end();

    $register = IPC::Shareable::global_register;
    $keys = keys %$register;
    IPC::Shareable::clean_up_protected($protect_lock);
    is $keys, 0, "IPC::Shareable shows no entries in the register after cleanup";
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