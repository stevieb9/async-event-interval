use warnings;
use strict;
use feature 'say';

use Async::Event::Interval;

my $event = Async::Event::Interval->new(
    2,
    sub {
        kill 9, $$;
    },
);

$event->start;

sleep 1;

if ($event->status == -1){
    say "event crashed, restarting";
    $event->restart;
    say "status ok after restart" if $event->status;
}
