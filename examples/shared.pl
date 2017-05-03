use warnings;
use strict;

use Async::Event::Interval;
use IPC::Shareable;

my $glue = $$;
my $options = {
     create    => 1,
     exclusive => 0,
     mode      => 0644,
     destroy   => 1,
}; 

my %shared = (callback => 0);

my $share = tie(
    %shared, 
    'IPC::Shareable', 
    $glue, 
    $options
) or die "tie failed\n";

my $event_one
    = Async::Event::Interval->new(1.5, \&callback_one);

my $event_two
    = Async::Event::Interval->new(3, \&callback_two);

$event_one->start;
select(undef, undef, undef, 0.1);
$event_two->start;

sleep 10;

$event_one->stop;
$event_two->stop;

print "after events: $shared{a}\n";

$shared{a} += 1000000;

print "after mod: $shared{a}\n";

$share->remove;
$share->clean_up_all;

sub callback_one {
    $shared{a}++;
    print "one: $shared{a}\n";
}
sub callback_two {
    $shared{a} += 100;
    print "two $shared{a}\n";
}


__END__

one: 1
two 101
one: 102
one: 103
one: 104
two 204
one: 205
one: 206
one: 207
two 307
one: 308
one: 309
one: 310
two 410
one: 411
after events: 411
after mod: 1000411

