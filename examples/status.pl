use warnings;
use strict;
use feature 'say';

use Async::Event::Interval;

my $ev
    = Async::Event::Interval->new(1.5, \&cb);

$ev->start;
say $ev->status;

sleep 2;

say $ev->status;

$ev->stop;
say $ev->status;

sub cb {
    print "hey!\n";
#    die "blah\n";
}


