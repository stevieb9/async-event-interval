use warnings;
use strict;

use Async::Event::Interval;
use IPC::Shareable;

tie my %shared_data, 'IPC::Shareable', {
    key         => '123456789',
    create      => 1,
    destroy     => 1
};

my $event = Async::Event::Interval->new(1, \&update);

$event->start;

my $count = 0;

while (1) {
    last if $count == 20;
    sleep 1;
    $count++;
}

(tied %shared_data)->unspawn("hello world");

sub update {
    # Because each event runs in its own process, $$ will be set to the
    # process ID of the calling event, even though they both call this
    # same function

    $shared_data{$$}{called_count}++;
}