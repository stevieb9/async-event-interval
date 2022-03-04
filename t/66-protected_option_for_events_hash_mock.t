use strict;
use warnings;

use Async::Event::Interval;
use Data::Dumper;
use IPC::Shareable;
use Mock::Sub;
use Test::More;

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
    is $keys, 2, "The \%events hash shm segment nor its cild wasn't removed ok";

    $sub->unmock;

    $register = IPC::Shareable::global_register;
    $keys = keys %$register;
    IPC::Shareable::clean_up_protected($protect_lock);
    is $keys, 0, "IPC::Shareable shows no entries in the register after cleanup";
}

done_testing();