use strict;
use warnings;

use Async::Event::Interval;
use Test::More;

require IPC::Shareable;
import IPC::Shareable;
use Data::Dumper;

# duplicate key
# scalar values only
# multiple scalars per event
# class or object based?

if (! $ENV{CI_TESTING}) {
    plan skip_all => "Not on a valid CI testing platform..."
}

my $mod = 'Async::Event::Interval';

tie my $scalar, 'IPC::Shareable', { destroy => 1 };

$scalar = -1;

is $scalar, -1, "shared var has original value before event start" ;

my $e = $mod->new(0.2, \&perform);
$e->start;
select(undef, undef, undef, 0.4);
$e->stop;

is $scalar, 99, "shared var has updated value after event start" ;

sub perform {
    $scalar = 99;
}

done_testing();
