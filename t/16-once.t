use strict;
use warnings;

use Async::Event::Interval;
use Time::HiRes qw(usleep);
use Test::More;

my $mod = 'Async::Event::Interval';

my $e = $mod->new(0, sub {});
$e->start;

sleep 1;

is $e->status, -1, "Zero as interval runs event only once";

done_testing();
