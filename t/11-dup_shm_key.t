use strict;
use warnings;

use IPC::Shareable;
use Mock::Sub;
use Test::More;

my ($segs_before, $sems_before);
BEGIN {
    $segs_before = IPC::Shareable::seg_count();
    $sems_before = IPC::Shareable::sem_count();
}

use Async::Event::Interval;

warn "Segs Before: $segs_before\n" if $ENV{PRINT_SEGS};
warn "Sems Before: $sems_before\n" if $ENV{PRINT_SEGS};

my $mock = Mock::Sub->new;
my $shm_key = $mock->mock('Async::Event::Interval::_rand_shm_key');

my $mod = 'Async::Event::Interval';

{
    my $e = $mod->new(0, sub {});

    $shm_key->return_value('TEST');

    my $var;

    $var = $e->shared_scalar;
    is $shm_key->called_count, 1, "_rand_shm_key() called once to set key initially ok";

    my $catch = eval { $var = $e->shared_scalar; 1; };
    is $shm_key->called_count, 11, "_rand_shm_key() croaks after 10 failed attempts at unique key creation";
    is $catch, undef, "_rand_shm_key() croaks if it couldn't generate a unique key";
    like $@, qr/Could not generate a unique shared/, "...and error message is sane";
}

$shm_key->unmock;

Async::Event::Interval::_end();
IPC::Shareable::_end;

my $segs_after = IPC::Shareable::seg_count();
my $sems_after = IPC::Shareable::sem_count();
warn "Segs After: $segs_after\n" if $ENV{PRINT_SEGS};
warn "Sems After: $sems_after\n" if $ENV{PRINT_SEGS};

is $segs_after, $segs_before, "All segs cleaned up ok";
is $sems_after, $sems_before, "All semaphore sets cleaned up ok";

done_testing();