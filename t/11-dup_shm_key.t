use strict;
use warnings;

use Async::Event::Interval;
use Data::Dumper;
use IPC::Shareable;
use Mock::Sub;
use Test::More;

my $mock = Mock::Sub->new;
my $shm_key = $mock->mock('Async::Event::Interval::_rand_shm_key');

my $mod = 'Async::Event::Interval';
my $e = $mod->new(0, sub {});

$shm_key->return_value('TEST');

my $var;

$var = $e->shared_scalar;
is $shm_key->called_count, 1, "_rand_shm_key() called once to set key initially ok";

my $catch = eval { $var = $e->shared_scalar; 1; };
is $shm_key->called_count, 11, "_rand_shm_key() croaks after 10 failed attempts at unique key creation";
is $catch, undef, "_rand_shm_key() croaks if it couldn't generate a unique key";
like $@, qr/Could not generate a unique shared/, "...and error message is sane";

done_testing();
