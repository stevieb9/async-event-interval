use strict;
use warnings;

use IPC::Shareable;
use Test::More;
use Time::HiRes qw(usleep);

my ($segs_before, $sems_before);
BEGIN {
    $segs_before = IPC::Shareable::seg_count();
    $sems_before = IPC::Shareable::sem_count();
}

use Async::Event::Interval;

warn "Segs Before: $segs_before\n" if $ENV{PRINT_SEGS};
warn "Sems Before: $sems_before\n" if $ENV{PRINT_SEGS};

my $mod = 'Async::Event::Interval';

my $file = 't/test.data';

{
    my $e = $mod->new(0.2, \&perform, 10);

    $e->restart;

    is -e $file, undef, "event is asynchronious";

    sleep 2;

    $e->stop;

    my $data;
    {
        local $/;
        open my $fh, '<', $file or die $!;
        $data = <$fh>;
    }

    is $data, 10, "single event does the right thing";

    unlink $file or die $!;
    is -e $file, undef, "temp file removed ok";
}

sub perform {
    my $arg = shift;
    sleep 1;
    open my $wfh, '>', $file or die $!;
    print $wfh $arg;
    close $wfh;
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