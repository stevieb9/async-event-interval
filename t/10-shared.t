use strict;
use warnings;

use Data::Dumper;
use Test::More;

BEGIN {
    if (! $ENV{CI_TESTING}) {
        plan skip_all => "Not on a valid CI testing platform...";
    }
    warn "Segs before: " . `ipcs -m | wc -l` . "\n" if $ENV{PRINT_SEGS};
}

use Async::Event::Interval;
use IPC::Shareable;

my $mod = 'Async::Event::Interval';
my $e = $mod->new(0.5, \&perform);
my $x = $mod->new(0, \&multi);

my $scalar_a = $e->shared_scalar;
my $scalar_b = $e->shared_scalar;

is ref $scalar_a, 'SCALAR', "shared var a is a scalar when initialized" ;
is ref $scalar_b, 'SCALAR', "shared var b is a scalar when initialized" ;

$$scalar_a = -1;
is $$scalar_a, -1, "shared var a has original value -1 before event start" ;
$$scalar_b = -2;
is $$scalar_b, -2, "shared var b has original value -2 before event start" ;

$e->start;
sleep 1;
$e->stop;

is $$scalar_a, 99, "shared var a has updated value after event start" ;
is $$scalar_b, 98, "shared var b has updated value after event start" ;

$x->start;
sleep 1;
$x->stop;

is $$scalar_a, 'hello, world', "shared var a has updated value in separate event" ;

sub perform {
    $$scalar_a = 99;
    $$scalar_b = 98;
}

sub multi {
    $$scalar_a = 'hello, world';
}

warn "Segs before: " . `ipcs -m | wc -l` . "\n" if $ENV{PRINT_SEGS};

done_testing();
