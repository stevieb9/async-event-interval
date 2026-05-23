use strict;
use warnings;

use IPC::Shareable;
use Test::More;

my ($segs_before, $sems_before);
BEGIN {
    $segs_before = IPC::Shareable::seg_count();
    $sems_before = IPC::Shareable::sem_count();
}

use Async::Event::Interval;

warn "Segs Before: $segs_before\n" if $ENV{PRINT_SEGS};
warn "Sems Before: $sems_before\n" if $ENV{PRINT_SEGS};

my $mod = 'Async::Event::Interval';

tie my $num, 'IPC::Shareable', { destroy => 1 };

$num = 1;

my $e = $mod->new(
    0.1,
    sub {
        die("critical") if $num == 8;
        $num++;
    }
);

# Start

$e->start;

select(undef, undef, undef, 1);

is $e->events->{$e->id}{runs}, 8, "events() has proper count of runs ok";
is $e->info->{runs}, 8, "...so does info()";
is $e->runs, 8, "...so does runs()";

is $e->events->{$e->id}{errors}, 1, "events() has proper count of errors ok";
is $e->info->{errors}, 1, "...so does info()";
is $e->errors, 1, "...so does errors()";

like
    $e->events->{$e->id}{error_message},
    qr/critical/,
    "events() has proper error message ok";
like
    $e->info->{error_message},
    qr/critical/,
    "...so does info()";
like
    $e->error_message,
    qr/critical/,
    "...so does error_message";

is $e->status, 0, "status() is waiting on error ok";
is $e->error, 1, "error() is set on error ok";
is $e->waiting, 1, "waiting() is set on error ok";

# Restart

$num = 1;
$e->restart if $e->waiting;

select(undef, undef, undef, 1);

is $e->events->{$e->id}{runs}, 16, "events() has proper count of runs after restart ok";
is $e->info->{runs}, 16, "...so does info()";
is $e->runs, 16, "...so does runs()";

is $e->events->{$e->id}{errors}, 2, "events() has proper count of errors after restart ok";
is $e->info->{errors}, 2, "...so does info()";
is $e->errors, 2, "...so does errors()";

like
    $e->events->{$e->id}{error_message},
    qr/critical/,
    "events() has proper error message after restart ok";
like
    $e->info->{error_message},
    qr/critical/,
    "...so does info()";
like
    $e->error_message,
    qr/critical/,
    "...so does error_message";

is $e->status, 0, "status() is waiting on error after restart ok";
is $e->error, 1, "error() is set on error after restart ok";
is $e->waiting, 1, "waiting() is set on error after restart ok";

$e->stop;

Async::Event::Interval::_end();
IPC::Shareable::_end;

my $segs_after = IPC::Shareable::seg_count();
my $sems_after = IPC::Shareable::sem_count();
warn "Segs After: $segs_after\n" if $ENV{PRINT_SEGS};
warn "Sems After: $sems_after\n" if $ENV{PRINT_SEGS};

is $segs_after, $segs_before, "All segs cleaned up ok";
is $sems_after, $sems_before, "All semaphore sets cleaned up ok";

done_testing();