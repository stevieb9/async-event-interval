use strict;
use warnings;

use Async::Event::Interval;
use IPC::Shareable qw(:lock);
use Test::More;

unless ( $ENV{DEV_TESTING} ) {
    print "dev test only!\n";
    plan( skip_all => "This is an author test" );
}

my $mod = 'Async::Event::Interval';

my $href = {a => 0, b => 1};

tie $href, 'IPC::Shareable', undef;

my $e = $mod->new(1, \&perform);
$e->start;

sleep 1.1;
is $href->{a}, 10, "ok" ;

sleep 1;
$e->stop;
ok $href->{a} > 10, "ok" ;


sub perform {
    $href->{a} += 10;
}

done_testing();
