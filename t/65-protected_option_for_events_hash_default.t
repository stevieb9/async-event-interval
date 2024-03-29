use strict;
use warnings;

use Data::Dumper;
use Mock::Sub;
use Test::More;

BEGIN {
    if (! $ENV{CI_TESTING}) {
        plan skip_all => "Not on a valid CI testing platform...";
    }
    warn "Segs before: " . `ipcs -m | wc -l` . "\n" if $ENV{PRINT_SEGS};
}

use Async::Event::Interval;
use IPC::Shareable;

my $mod = 'Async::Event::Interval';

# Proper cleanup
{
    my ($keys, $register);

    {
        $register = IPC::Shareable::global_register;
        $keys = keys %$register;
        is $keys, 1, "IPC::Shareable shows one entry before event creation ok";

        my $e = $mod->new(0, sub {});

        $register = IPC::Shareable::global_register;
        $keys = keys %$register;
        is $keys, 2, "IPC::Shareable shows two entries after event creation ok";
    }

    # Force the END block for cleanup
    Async::Event::Interval::_end();

    $register = IPC::Shareable::global_register;
    $keys = keys %$register;
    is $keys, 0, "IPC::Shareable shows no entries after object out of scope ok";
}

warn "Segs after: " . `ipcs -m | wc -l` . "\n" if $ENV{PRINT_SEGS};

done_testing();