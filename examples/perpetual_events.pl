use warnings;
use strict;

my %events;

for (0..4) {
    $events{$_} = Async::Event::Interval->new(0, \&work, $_)
}

sub work {
    my ($event_num, $broadcast_id) = @_;
    print "Event $event_num working on bcast $broadcast_id\n";
    sleep $event_num + 2;
}