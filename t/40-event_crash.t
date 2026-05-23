use strict;
use warnings;

use lib 't/lib';
use TestHelper;
use Test::More;

use Async::Event::Interval;

{
    my $event = Async::Event::Interval->new(
        0.3,
        sub {
            kill 9, $$;
        },
    );

    $event->start;

    is $event->status > 0, 1, "status ok at start";

    select(undef, undef, undef, 0.6);

    is $event->status, 0, "upon crash, status return ok";
    is $event->error, 1, "upon crash, error return ok";

    if ($event->error){
        $event->restart;
        is $event->status > 0, 1, "after restart, status ok again";
        is $event->error, 0, "...so is error";
    }

    $event->stop;
}
