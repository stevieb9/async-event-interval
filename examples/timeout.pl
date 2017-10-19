use warnings;
use strict;
use feature 'say';

use Async::Event::Interval;

my $timeout = 1;

my $event = Async::Event::Interval->new(
    1,
    sub {
        local $SIG{ALRM} = sub { kill 9, $$; };
        alarm $timeout;
        # do stuff here. If it takes too long, we kill ourselves
        sleep 2;
        alarm 0;
    },
);

$event->start;

for (1..10){
    say "status ok" if $event->status;
    say $event->status;

    if ($event->status == -1){
        say "event crashed, restarting";
        $event->restart;
        say "status ok after restart" if $event->status;
    }

    sleep 1;
}


