use strict;
use warnings;

use lib 't/lib';
use TestHelper;
use Test::More;

use Async::Event::Interval;

# timeout() getter/setter + per-callback alarm wrapping in
# _run_callback(). Default is undef (no timeout). Set a positive
# integer to have the callback self-terminate if it exceeds the limit.

# timeout() returns undef by default.
{
    my $e = Async::Event::Interval->new(0.5, sub {});
    is $e->timeout, undef, "timeout() returns undef by default";
}

# timeout(5) sets and returns the value.
{
    my $e = Async::Event::Interval->new(0.5, sub {});
    $e->timeout(5);
    is $e->timeout, 5, "timeout(5) sets and returns 5";
}

# Negative value croaks.
{
    my $e = Async::Event::Interval->new(0.5, sub {});
    my $ok = eval { $e->timeout(-1); 1 };
    my $err = $@;
    is $ok, undef, "timeout(-1) croaks";
    like $err, qr/must be a positive/, "...with positive requirement message";
}

# Non-numeric value croaks.
{
    my $e = Async::Event::Interval->new(0.5, sub {});
    my $ok = eval { $e->timeout("abc"); 1 };
    my $err = $@;
    is $ok, undef, "timeout('abc') croaks";
    like $err, qr/must be a positive integer/,
        "...with validation message";
}

# timeout(0) disables the timeout.
{
    my $e = Async::Event::Interval->new(0.5, sub {});
    $e->timeout(5);
    is $e->timeout, 5, "timeout set to 5";
    $e->timeout(0);
    is $e->timeout, 0, "timeout(0) disables";
}

# timeout(undef) also disables.
{
    my $e = Async::Event::Interval->new(0.5, sub {});
    $e->timeout(5);
    is $e->timeout, 5, "timeout set to 5";
    $e->timeout(undef);
    is $e->timeout, undef, "timeout(undef) disables";
}

# Run-once: callback completes under timeout, no error.
{
    my $e = Async::Event::Interval->new(0, sub {});
    $e->timeout(2);
    $e->start;
    select(undef, undef, undef, 0.25);
    is $e->runs,  1, "run-once under timeout: callback ran";
    is $e->errors, 0, "run-once under timeout: no errors";
}

# Run-once: callback exceeds timeout, error recorded.
{
    my $e = Async::Event::Interval->new(0, sub {
        select(undef, undef, undef, 5);
    });
    $e->timeout(1);
    $e->start;
    select(undef, undef, undef, 2);
    is $e->errors, 1, "run-once over timeout: errors incremented";
    like $e->error_message, qr/timed out after 1s/,
        "run-once over timeout: error_message records timeout";
}

# Interval mode: callback completes under timeout, multiple iterations.
{
    my $count = 0;
    my $e = Async::Event::Interval->new(0.1, sub { $count++ });
    $e->timeout(2);
    $e->start;
    select(undef, undef, undef, 0.5);
    $e->stop;
    cmp_ok $e->runs, '>=', 2, "interval under timeout: ran at least twice";
    is $e->errors, 0, "interval under timeout: no errors";
}

# Interval mode: callback exceeds timeout, child exits with error.
{
    my $e = Async::Event::Interval->new(0.1, sub {
        select(undef, undef, undef, 5);
    });
    $e->timeout(1);
    $e->start;
    select(undef, undef, undef, 2);
    is $e->errors, 1, "interval over timeout: errors incremented";
    like $e->error_message, qr/timed out after 1s/,
        "interval over timeout: error_message records timeout";
}

# info() snapshot includes the timeout value.
{
    my $e = Async::Event::Interval->new(0.5, sub {});
    $e->timeout(30);
    is $e->info->{timeout}, 30, "info() includes timeout value";
}

# events() snapshot includes the timeout value.
{
    my $e = Async::Event::Interval->new(0.5, sub {});
    $e->timeout(15);
    my $snap = Async::Event::Interval::events();
    is $snap->{$e->id}{timeout}, 15, "events() includes timeout value";
}

# Timeout persists across restart.
{
    my $e = Async::Event::Interval->new(0, sub {
        select(undef, undef, undef, 5);
    });
    $e->timeout(1);
    $e->start;
    select(undef, undef, undef, 2);
    is $e->errors, 1, "first run timed out";

    $e->error;  # trigger _detect_crash so _started is cleared

    $e->restart;
    select(undef, undef, undef, 2);
    is $e->errors, 2, "second run also timed out (timeout persisted)";
    like $e->error_message, qr/timed out after 1s/,
        "error_message still matches timeout pattern after restart";
}
