use warnings;
use strict;
use feature 'say';

use Async::Event::Interval;

my $ev
    = Async::Event::Interval->new(1.5, \&cb);

$ev->start;
say $ev->status;
say $ev->error;

sleep 2;

say $ev->status;
say $ev->error;

$ev->stop;
say $ev->status;
say $ev->error;

sub cb {
    print "hey!\n";
#    die "blah\n";
}

