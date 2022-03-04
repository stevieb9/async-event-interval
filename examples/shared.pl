use warnings;
use strict;

use Async::Event::Interval;
use IPC::Shareable;

tie my %shared_data, 'IPC::Shareable', {
    key         => '123456789',
    create      => 1,
    exclusive   => 0,
    destroy     => 1
};

$shared_data{$$}++;

my $event_one = Async::Event::Interval->new(
    0.2,
    sub { $shared_data{$$}++; }
);

my $event_two = Async::Event::Interval->new(
    1,
    sub { $shared_data{$$}++; }
);

$event_one->start;
$event_two->start;

sleep 10;

$event_one->stop;
$event_two->stop;

for my $pid (keys %shared_data) {
    printf("Process ID %d executed %d times\n", $pid, $shared_data{$pid});
}

for my $event ($event_one, $event_two) {
    printf(
        "Event ID %d with PID %d ran %d times, with %d errors and an interval" .
        " of %.2f seconds\n",
        $event->id,
        $event->pid,
        $event->runs,
        $event->errors,
        $event->interval
    );
}

(tied %shared_data)->remove;