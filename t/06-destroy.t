use strict;
use warnings;

use Async::Event::Interval;
use Data::Dumper;
use Test::More;

$SIG{__WARN__} = sub {
    my ($warning) = @_;
};

my $mod = 'Async::Event::Interval';

#my $hold = $mod->new(0, sub {});

{
    my $e = $mod->new(0, sub {});
}

is
    eval {my $e = $mod->new(0, sub {}); 1; },
    undef,
    "If "
done_testing();