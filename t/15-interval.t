use strict;
use warnings;

use Async::Event::Interval;
use Test::More;

my $mod = 'Async::Event::Interval';

# Test timed interval

my $e = $mod->new(1, \&perform);

my $x = $e->shared_scalar;
$$x = 0;

is $$x, 0, "baseline var ok";

$e->start;

sleep 2;

is $$x > 0 && $$x < 30, 1, "event is async and correct";

sleep 2;
$e->stop;

is $$x >= 30, 1, "event is async, and is correct again";

sub perform {
    $$x += 10;
}

done_testing();
