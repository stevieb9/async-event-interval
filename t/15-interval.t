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

# decimal interval

my $e2 = Async::Event::Interval->new(1.7, \&timed);
my $t = $e2->shared_scalar;
$$t = time;
$e2->start;
sleep 2;
$e2->stop;

sub perform {
    $$x += 10;
}
sub timed {
    my $time = time;
    is $time - $$t > 1.5 && $time - $$t < 2, 1, "Event is 1.7 seconds ok";
}
done_testing();
