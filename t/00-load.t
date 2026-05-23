use 5.006;
use strict;
use warnings;

use IPC::Shareable;
use Test::More;

my ($segs_before, $sems_before);
BEGIN {
    $segs_before = IPC::Shareable::seg_count();
    $sems_before = IPC::Shareable::sem_count();
}

use_ok('Async::Event::Interval') || print "Bail out!\n";

use Async::Event::Interval;

diag("Testing Async::Event::Interval $Async::Event::Interval::VERSION, Perl $], $^X");

warn "Segs Before: $segs_before\n" if $ENV{PRINT_SEGS};
warn "Sems Before: $sems_before\n" if $ENV{PRINT_SEGS};

# Persist the pre-suite seg/sem counts to a flat file so the final
# 99-end_check.t can verify the suite as a whole leaked nothing.

my $tmpfile = '/tmp/async_event_interval_seg_count';

# Clear any stale data from a previous interrupted run

unlink $tmpfile if -e $tmpfile;

open my $fh, '>', $tmpfile or die "Can't open $tmpfile for write: $!";
print $fh "$segs_before\n$sems_before\n";
close $fh;

{
    my $e = Async::Event::Interval->new(0, sub {});
}

done_testing;