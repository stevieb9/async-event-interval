use 5.006;
use strict;
use warnings;

use IPC::Shareable;
use Test::More;

my $tmpfile = '/tmp/async_event_interval_seg_count';

# Guarantee the tmp file is removed even if an assertion below fails or
# the test bails early.

END {
    unlink $tmpfile if defined $tmpfile && -e $tmpfile;
}

warn "Segs Before: " . IPC::Shareable::seg_count() . "\n" if $ENV{PRINT_SEGS};
warn "Sems Before: " . IPC::Shareable::sem_count() . "\n" if $ENV{PRINT_SEGS};

open my $fh, '<', $tmpfile or die "Can't open $tmpfile for read: $!";
chomp(my $start_segs = <$fh>);
chomp(my $start_sems = <$fh>);
close $fh;

my $segs = IPC::Shareable::seg_count();
my $sems = IPC::Shareable::sem_count();

warn "Segs After: $segs\n" if $ENV{PRINT_SEGS};
warn "Sems After: $sems\n" if $ENV{PRINT_SEGS};

is $segs, $start_segs, "Started and ended test suite with $start_segs segs ok";
is $sems, $start_sems, "Started and ended test suite with $start_sems sems ok";

done_testing();