use warnings;
use strict;

use Parallel::ForkManager;

my $continue = 1;
$SIG{INT} = sub {
    print "cleaning up...\n";
    $continue = 0;
};

my $pm = Parallel::ForkManager->new(1);
my $c = 0;
my $callback = sub {print "$_[0]\n";};

event($callback);

sub event {
    my $cb = shift;

    for (0..1){
        my $pid = $pm->start and last;

        while($continue){
            $cb->($c);
            sleep 1;
            $c++;
        }
        $pm->finish;
    }
    $pm->wait_all_children;
}

print "after async started...\n";

sleep 3;

print "after sleep...\n";

sleep 2;

print "waiting for async proc...\n";

$pm->wait_all_children;
