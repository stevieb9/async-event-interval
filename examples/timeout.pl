use warnings;
use strict;
use feature 'say';

use Async::Event::Interval;

my $timeout = 3;

my $event = Async::Event::Interval->new(
    2,
    sub {
        local $SIG{ALRM} = sub { print "Committing suicide!\n"; kill 9, $$; };
        alarm $timeout;
        # do stuff here. If it takes too long, we kill ourselves
        sleep 4;
        alarm 0;
    },
);

$event->start;
say "status ok" if $event->status;

for (1..5){

    sleep 1;

    if ($event->error){
        say "event crashed, restarting";
        $event->restart;
        say "status ok after restart" if $event->status;
    }

    printf "status %d, error: %d, pid: %d\n", $event->status ? 1 : 0, $event->error, $event->_pid;

}
