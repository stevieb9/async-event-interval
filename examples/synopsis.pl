use warnings;
use strict;

use Async::Event::Interval;

my $event = Async::Event::Interval->new(2, \&callback);

my $shared_scalar_json = $event->shared_scalar;

$event->start;

while (1) {
    print "$$shared_scalar_json\n" if defined $$shared_scalar_json;

    # Do other things
}

sub callback {
    $$shared_scalar_json = ...; # Fetch JSON from website
}