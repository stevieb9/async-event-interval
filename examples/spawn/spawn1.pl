use warnings;
use strict;

use Async::Event::Interval;
use Data::Dumper;
use IPC::Shareable;

tie my %shared_data, 'IPC::Shareable', {
    key         => '123456789',
    create      => 1,
    destroy     => 1
};

(tied %shared_data)->spawn(key => "hello world");

my $event = Async::Event::Interval->new(1, \&update);

$event->start;

my $count = 0;

while (1) {
    last if $count == 5;
    sleep 1;
    $count++;
}

print Dumper \%shared_data;

sub update {
    $shared_data{$$}{spawn1}++;
}