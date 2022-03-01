use warnings;
use strict;
use feature 'say';

use Async::Event::Interval;

my $event = Async::Event::Interval->new(
    0.2,
    sub {
        kill 9, $$;
    },
);

$event->start;

sleep 1;

if ($event->error){
    say "event crashed, restarting";
    $event->restart;
    say "status ok after restart" if $event->status;
    say "error state ok after restart" if ! $event->error;
}
