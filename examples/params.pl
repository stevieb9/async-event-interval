use warnings;
use strict;

# displays how to send in params to your event
# callback sub

use Async::Event::Interval;

my @params = qw(1 2 3);

my $event = Async::Event::Interval->new(
    1,
    \&callback,
    @params
);

$event->start;

sleep 2; # your app does other stuff here

sub callback {
    my ($one, $two, $three) = @_;
    print "$one, $two, $three\n";
}

$event->stop;
