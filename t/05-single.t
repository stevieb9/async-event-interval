use strict;
use warnings;

use Async::Event::Interval;
use Time::HiRes qw(usleep);
use Test::More;

my $mod = 'Async::Event::Interval';

my $e = $mod->new;
my $x = 0;

$e->event(1, \&perform);

print "started...\n";

sleep 2;

for (1000..1010){
    print "* $_\n";
    usleep 750000;
}

print "stopping in 2 secs...\n";

sleep 2;

$e->stop;

sleep 1;

print "restarting...\n";

$e->restart;

print "restarted, DESTROY in 2 secs...\n";

sleep 2;

$e->DESTROY;

sub perform {
    print "$x\n";
    $x++;
}
