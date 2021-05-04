use warnings;
use strict;

use Async::Event::Interval;

my $event = Async::Event::Interval->new(2, \&callback);

my $shared_scalar_json      = $event->shared_scalar;
my $shared_scalar_data_flag = $event->shared_scalar;

$$shared_scalar_data_flag = 0;

$event->start;

while (1) {

    if ($$shared_scalar_data_flag) {
        print "$$shared_scalar_json\n";
        $$shared_scalar_data_flag = 0;
    }
}

sub callback {

    my $json = ...; # Fetch JSON from a website

    if ($json) {
        $$shared_scalar_json = $json;
        $$shared_scalar_data_flag = 1;
    }
}