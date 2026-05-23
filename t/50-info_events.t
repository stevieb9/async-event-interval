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

my $one = $mod->new(0, sub {});
my $two = $mod->new(0, sub {});

my $events = Async::Event::Interval::events();

is ref $events, 'HASH', 'Class events() returns a hash ref ok';

is keys %$events, 2, "Two events have been created ok";

for (keys %$events) {
    like $_, qr/^\w+$/, "Events key $_ is a word ok";
    is ref $events->{$_}, 'HASH', "Event $_ is a hash ref ok";
    is keys %{ $events->{$_} }, 1, "After creation, event $_ hash has a single entry";
}

$one->start;
$two->start;

select(undef, undef, undef, 0.2);

$events = Async::Event::Interval::events();

for (keys %$events) {
    like $_, qr/^\d+$/, "Events key $_ is still an integer ok";
    is $events->{$_}{runs} > 0, 1, "Event $_ has a 'runs' key set ok";
    is ref $events->{$_}, 'HASH', "Event $_ is still a hash ref ok";
    is keys %{ $events->{$_} }, 3, "After creation, event $_ hash has 3 keys";
    like $events->{$_}{pid}, qr/^\d+$/, "Event $_ has pid key with a proper PID";
    like $events->{$_}{interval}, qr/^(\d+\.)?\d+$/, "Event $_ has interval key with a proper interval";
}

my $a = $one->shared_scalar;
my $b = $two->shared_scalar;
my $aa = $one->shared_scalar;
my $bb = $two->shared_scalar;

$events = Async::Event::Interval::events();

for (keys %$events) {
    like $_, qr/^\d+$/, "Events key $_ is still an integer ok";
    is ref $events->{$_}, 'HASH', "Event $_ is still a hash ref ok";
    is keys %{ $events->{$_} }, 4, "After creation, event $_ hash has proper number of keys ok";
    like $events->{$_}{pid}, qr/^\d+$/, "Event $_ has pid key with a proper PID";
    is ref $events->{$_}{shared_scalars}, 'HASH', "Event $_ has shared_scalars href";
    is keys %{ $events->{$_}{shared_scalars} }, 2, "Event $_ has two shared scalars";
    is $events->{$_}{runs} > 0, 1, "Event $_ has a 'runs' key set ok";
    like $events->{$_}{interval}, qr/^(\d+\.)?\d+$/, "Event $_ has interval key with a proper interval";

    for my $shared_key (keys %{ $events->{$_}{shared_scalars} }) {
        like $shared_key, qr/^[A-Z]{12}$/, "Shared scalar key $shared_key is a string of 12 letters ok";
        is ref $events->{$_}{shared_scalars}{$shared_key}, 'SCALAR', "Shared scalar $shared_key is a scalar ref";
        is ${ $events->{$_}{shared_scalars}{$shared_key} }, undef, "...and is undef";
    }
}

my $id = 0;

for ($one, $two) {
    is $_->info()->{pid}, $events->{$id}{pid}, "info() pid matches for event $id";

    like $_->info()->{interval}, qr/^(\d+\.)?\d+$/, "info() has interval key with a proper interval for event $id";
    for my $shared_key (keys %{$_->info->{shared_scalars}}) {
        like $shared_key, qr/^[A-Z]{12}$/, "Shared scalar key $shared_key is a string of 12 letters ok";
        is ref $_->info->{shared_scalars}{$shared_key}, 'SCALAR', "Shared scalar $shared_key is a scalar ref";
        is ${$_->info->{shared_scalars}{$shared_key}}, undef, "...and is undef";
    }

    my $actual_id = $_->id;

    is $actual_id, $id, "Event $actual_id has proper id()";

    $id++;
}

Async::Event::Interval::_end();
IPC::Shareable::_end;

my $segs_after = IPC::Shareable::seg_count();
my $sems_after = IPC::Shareable::sem_count();
warn "Segs After: $segs_after\n" if $ENV{PRINT_SEGS};
warn "Sems After: $sems_after\n" if $ENV{PRINT_SEGS};

is $segs_after, $segs_before, "All segs cleaned up ok";
is $sems_after, $sems_before, "All semaphore sets cleaned up ok";

done_testing();