package Async::Event::Interval;

use warnings;
use strict;

our $VERSION = '1.14';

use Carp qw(croak);
use Data::Dumper;
use IPC::Shareable qw(:lock);
use Parallel::ForkManager;

use constant {
    SHM_CREATE_RETRIES => 100,
    END_LOCK_TIMEOUT   => 2,
};

my $id = 0;

$SIG{CHLD} = 'IGNORE';

my %events;
my $shared_memory_protect_lock = _rand_shm_lock();

_create_events_seg();

sub _create_events_seg {
    my $created;
    my $tries = 0;

    while (! $created) {
        if ($tries++ >= SHM_CREATE_RETRIES) {
            croak
                "Unable to create the %events shared memory segment after "
              . SHM_CREATE_RETRIES
              . " attempts: $@";
        }

        $created = eval {
            tie %events, 'IPC::Shareable', {
                key         => _rand_shm_key(),
                create      => 1,
                exclusive   => 1,
                protected   => _shm_lock(),
                mode        => 0600,
                destroy     => 1
            };
            1;
        };
    }

    return $created;
}

*restart = \&start;

# Helpers that wrap every read/write of %events in the appropriate lock.
# _write_events takes LOCK_EX (using IPC::Shareable's coderef form, which
# auto-releases even on die). _read_events takes LOCK_SH, runs the
# coderef, then always unlocks before propagating any error. Both return
# the coderef's scalar return value. They no-op gracefully if the tie
# has been torn down (e.g. during global destruction).

sub _write_events {
    my ($cb) = @_;
    my $knot = tied(%events);
    return $cb->() unless $knot;

    my $r;
    $knot->lock(LOCK_EX, sub {
        $r = $cb->();
    });
    return $r;
}

sub _read_events {
    my ($cb) = @_;
    my $knot = tied(%events);
    return $cb->() unless $knot;

    $knot->lock(LOCK_SH);
    my $r;
    my $ok = eval { $r = $cb->(); 1 };
    my $err = $@;
    $knot->unlock;
    die $err if !$ok;
    return $r;
}

sub new {
    my $self = bless {}, shift;

    $self->id($id);
    $id++;

    _write_events(sub { $events{$self->id} = {} });

    $self->_pm;
    $self->_setup(@_);
    $self->_started(0);

    return $self;
}
sub error {
    my ($self) = @_;
    $self->status;
    return $self->pid && $self->pid == -99 ? 1 : 0;
}
sub errors {
    my ($self) = @_;
    return $self->_errors || 0;
}
sub error_message {
    my ($self) = @_;
    return $self->_error_message;
}
sub events {
    return _read_events(sub {
        my %copy;
        for my $id (keys %events) {
            my $event = $events{$id};
            $copy{$id} = { %$event };
            if ($copy{$id}{shared_scalars}) {
                $copy{$id}{shared_scalars} = [ @{ $copy{$id}{shared_scalars} } ];
            }
        }
        return \%copy;
    });
}

# Internal: return the IPC::Shareable knot for %events so test code
# can inspect semaphore state directly.
sub _events_knot {
    return tied(%events);
}
sub id {
    my ($self, $id) = @_;
    $self->{id} = $id if defined $id;
    return $_[0]->{id};
}
sub info {
    my ($self) = @_;
    return _read_events(sub {
        my $event = $events{$self->id} or return undef;
        my %copy = %$event;
        $copy{shared_scalars} = [ @{ $copy{shared_scalars} } ]
            if $copy{shared_scalars};
        return \%copy;
    });
}
sub interval {
    my ($self, $interval) = @_;

    if (defined $interval) {
        if ($interval !~ /^\d+$/ && $interval !~ /^(\d+)?\.\d+$/) {
            croak "\$interval must be an integer or float";
        }
        _write_events(sub { $events{$self->id}{interval} = $interval });
    }

    return _read_events(sub { $events{$self->id}->{interval} });
}
sub pid {
    my ($self) = @_;
    return $self->_pid;
}
sub runs {
    my ($self) = @_;
    return $self->_runs || 0;
}
sub shared_scalar {
    my ($self) = @_;

    my $shm_key;
    my $unique_shm_key_found = 0;
    my $scalar;

    _write_events(sub {
        for (0..9) {
            $shm_key = _rand_shm_key();
            my $existing = $events{$self->id}{shared_scalars} || [];
            if (! grep { $_ eq $shm_key } @$existing) {
                $unique_shm_key_found = 1;
                last;
            }
        }
        return unless $unique_shm_key_found;

        tie $scalar, 'IPC::Shareable', $shm_key, {
            create    => 1,
            destroy   => 1,
            protected => _shm_lock(),
        };

        push @{ $events{$self->id}{shared_scalars} }, $shm_key;
    });

    if (! $unique_shm_key_found) {
        croak("Could not generate a unique shared memory segment.");
    }

    push @{ $self->{_shared_scalars} }, \$scalar;

    return \$scalar;
}
sub start {
    my ($self, @callback_params) = @_;
    if ($self->_started){
        warn "Event already running...\n";
        return;
    }
    $self->_started(1);
    $self->_event(@callback_params);
}
sub status {
    my ($self) = @_;

    if ($self->_started){
        if (! $self->pid){
            croak "Event is started, but no PID can be found. This is a " .
                "fatal error. Exiting...\n";
        }
        if ($self->pid > 0){
            if (kill 0, $self->pid){
                return $self->pid;
            }
            else {
                # proc must have crashed
                $self->_started(0);
                $self->_pid(-99);
                $self->error;
            }
        }
    }
    return 0;
}
sub stop {
    my $self = shift;

    if ($self->pid){
        kill 9, $self->pid;

        $self->_started(0);

        # time to ensure the proc was killed

        sleep 1;

        if (kill 0, $self->pid){
            croak "Event stop was called, but the process hasn't been killed. " .
                  "This is a fatal event. Exiting...\n";
        }
    }
}
sub waiting {
    my ($self) = @_;
    return 1 if $self->error || ! $self->status;
    return 0;
}

sub _args {
    my ($self, $args) = @_;

    if (defined $args) {
        $self->{args} = $args;
    }

    return $self->{args};
}
sub _cb {
    my ($self, $cb) = @_;

    if (defined $cb) {
        croak "Callback must be a code reference." if ref $cb ne 'CODE';
        $self->{cb} = $cb;
    }

    return $self->{cb};
}
sub _errors {
    my ($self, $increment) = @_;
    if (defined $increment) {
        _write_events(sub { $events{$self->id}->{errors}++ });
    }
    return _read_events(sub { $events{$self->id}->{errors} });
}
sub _error_message {
    my ($self, $msg) = @_;
    if (defined $msg) {
        _write_events(sub { $events{$self->id}->{error_message} = $msg });
    }
    return _read_events(sub { $events{$self->id}->{error_message} });
}
sub _event {
    my ($self, @event_params) = @_;

    my @callback_params = scalar @event_params
        ? @event_params
        : @{ $self->_args };

    local $SIG{__WARN__} = sub {
        my $warn = shift;
        warn $warn if $warn !~ /^child process/;
    };

    for (0..1){
        my $pid = $self->_pm->start;
        if (! defined $pid) {
            croak "fork() failed: $!";
        }
        if ($pid){
            # this is the parent process
            $self->_pid($pid);
            last;
        }

        # set the child's proc id

        $self->_pid($$);

        # if no interval, run only once

        if ($self->interval) {
            eval {
                while (1) {
                    select(undef, undef, undef, $self->interval);
                    $self->_run_callback(@callback_params);
                }
            };
            $self->_pm->finish($@ ? 1 : 0);
        }
        else {
            eval { $self->_run_callback(@callback_params) };
            $self->_pm->finish($@ ? 1 : 0);
        }
    }
}
sub _run_callback {
    my ($self, @params) = @_;

    my $ok = eval {
        $self->_cb->(@params);
        1;
    };

    if (! $ok) {
        my $err = $@;
        $self->_errors(1);
        $self->_error_message($err);
        $self->_runs(1);
        $self->status;
        die $err;
    }

    $self->_runs(1);
    $self->status;
}
sub _pm {
    my ($self) = @_;

    if (! exists $self->{pm}) {
        $self->{pm} = Parallel::ForkManager->new(1);
    }

    return $self->{pm};
}
sub _pid {
    my ($self, $pid) = @_;
    if (defined $pid) {
        $self->{pid} = $pid;
        _write_events(sub { $events{$self->id}->{pid} = $self->{pid} });
    }
    return $self->{pid} || undef;
}
sub _rand_shm_key {
    return sprintf('0x%x', int(rand(0x7FFFFFFF)));
}
sub _rand_shm_lock {
    # Used for the 'protected' option in the %events hash creation.
    #
    # IPC::Shareable 1.14+ persists 'protected' in a semaphore slot
    # (SEM_PROTECTED), which the system caps at semvmx (typically
    # 0..32767, and 0 means "unprotected"). Derive a stable, in-range
    # value from $$ so a forked subprocess inherits the same key.

    return 1 + ($$ % 32767);
}
sub _runs {
    my ($self, $increment) = @_;
    if (defined $increment) {
        _write_events(sub { $events{$self->id}->{runs}++ });
    }
    return _read_events(sub { $events{$self->id}->{runs} });
}
sub _setup {
    my ($self, $interval, $cb, @args) = @_;
    $self->interval($interval);
    $self->_cb($cb);
    $self->_args(\@args);
}
sub _shm_lock {
    return $shared_memory_protect_lock;
}
sub _started {
    my ($self, $started) = @_;
    $self->{started} = $started if defined $started;
    return $self->{started};
}
sub DESTROY {
    my $self = $_[0];

    if (defined $self) {
        $self->stop if $self->pid;
    }

    # On events with interval of zero, ForkManager runs finish(), which
    # calls our destroy method. We only want to blow away the %events
    # hash if we truly go out of scope

    return if (caller())[0] eq 'Parallel::ForkManager::Child';

    # Release any shared_scalar segments owned by this event. These are
    # tracked in $self->{_shared_scalars}, not inside %events, so they
    # can be cleaned up outside the %events lock.

    if ($self->{_shared_scalars}) {
        for my $scalar (@{ $self->{_shared_scalars} }) {
            next unless ref $scalar eq 'SCALAR';
            my $knot = tied $$scalar;
            eval { $knot->remove } if $knot;
        }
    }

    _write_events(sub {
        delete $events{$self->id};
    });
}
sub _end {
    # Guard against deadlocking forever on _read_events' LOCK_SH if a
    # crashed/stuck peer still holds LOCK_EX on the events knot. Bail
    # out after END_LOCK_TIMEOUT seconds and let the process exit.

    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm(END_LOCK_TIMEOUT);
        if (! _read_events(sub { scalar keys %events })) {
            IPC::Shareable::clean_up_protected(_shm_lock());
        }
        alarm(0);
    };
}
END {
    _end();
}
sub _vim{}

1;

__END__

=head1 NAME

Async::Event::Interval - Scheduled and one-off asynchronous events

=for html
<a href="https://github.com/stevieb9/async-event-interval/actions"><img src="https://github.com/stevieb9/async-event-interval/workflows/CI/badge.svg"/></a>
<a href='https://coveralls.io/github/stevieb9/async-event-interval?branch=master'><img src='https://coveralls.io/repos/stevieb9/async-event-interval/badge.svg?branch=master&service=github' alt='Coverage Status' /></a>


=head1 SYNOPSIS

A simple event that updates JSON data from a website using a shared scalar
variable, while allowing the main application to continue running in the
foreground. Multiple events can be simultaneously used if desired.

See L</EXAMPLES> for other various functionality of this module.

    use warnings;
    use strict;

    use Async::Event::Interval;

    my $event = Async::Event::Interval->new(2, \&callback);

    my $json = $event->shared_scalar;

    $event->start;

    while (1) {
        print "$$json\n";

        #... do other things

        $event->restart if $event->error;
    }

    sub callback {
        $$json = ...; # Fetch JSON from website
    }

=head1 DESCRIPTION

Very basic implementation of asynchronous events triggered by a timed interval.
If a time of zero is specified, we'll run the event only once.

=head1 METHODS - EVENT OPERATION

=head2 new($delay, $callback, @params)

Returns a new C<Async::Event::Interval> object. Does not create the event. Use
C<start> for that.

Parameters:

    $delay

Mandatory: The interval on which to trigger your event callback, in seconds.
Represent partial seconds as a floating point number. If zero is specified,
we'll simply run the event once and stop.

    $callback

Mandatory: A reference to a subroutine that will be called every time the
interval expires.

    @params

Optional, List: A list of parameters to pass to the callback. Note that these
are not shared parameters and are a copy only, so changes to them in the main
code will not be seen in the event, and vice-versa. See L</shared_scalar> if
you'd like to use variables that can be shared between the main application and
the events.

Also note: These parameters are sent into the event only once. Each
time the callback is called, they will receive the exact same set of params.

To have the event get different values in the params each time the callback is
called, see L</start(@params)>.

=head2 start(@params)

Starts the event timer. Each time the interval is reached, the event callback
is executed.

Parameters:

    @params

Optional, List: A list of parameters that the callback will receive each time
the callback is called. This is most effective in single-run mode so you can
send in different parameter values on each incarnation. The parameters can be
any type of any complexity. Your callback will get them in whatever order you
send them in as.

=head2 stop

Stops the event from being executed.

=head2 restart

Alias for C<start()>. Re-starts a C<stop()>ped event.

=head2 status

Returns the event's process ID (true) if it is running, C<0> (false) if it
isn't.

=head2 waiting

Returns true if the event is dormant and is ready for a C<start()> or
C<restart()> command. Returns false if the event is already running.

=head2 error

Returns true if an event crashed unexpectedly in the background, and is ready
for a C<start()> or C<restart()> command. Returns false if the event is not in
an error state.

=head2 interval($seconds)

Gets/sets the delay time (in seconds) between each execution of the event's
callback code. You can use this method to change the delay between calls
during the event's lifecycle.

Parameters:

    $seconds

Optional, Integer: The number of seconds (can be floating point) to delay
between executions.

Return: Integer, the number of seconds between execution runs. If we're in
a run-once scenario, the return will be zero C<0>.

=head2 shared_scalar

Returns a reference to a scalar variable that can be shared between the main
process and the events. This reference can be used within multiple events, and
multiple shared scalars can be created by each event.

To read from or assign to the returned scalar, you must dereference it. Eg.
C<$$shared_scalar = 1;>.

B<Lifetime>: The underlying shared memory segment is owned by the event
object that created it. When the event goes out of scope (and its
C<DESTROY> runs), every C<shared_scalar> it created is released. Do not
dereference the returned scalar reference after the owning event has been
destroyed; the segment will no longer exist. If you need a shared scalar
whose lifetime is independent of any event, tie it directly with
L<IPC::Shareable>.

=head1 METHODS - EVENT INFORMATION

=head2 errors

Returns the number of times a started or restarted event has crashed
unexpectedly.

=head2 error_message

Returns the error message (if any) that caused the most recent event crash.

=head2 events

Returns a plain hash reference containing a snapshot of the data for all
existing events. The returned hash is a B<copy> — modifying it will not
affect the live events. C<shared_scalars> is an arrayref of the hex key
strings for each shared scalar created by the event; use the scalar
reference returned by L</shared_scalar> to read or write values.

The snapshot is taken under a read lock (C<LOCK_SH>) for consistency.

    $VAR1 = {
        '0' => {
            'shared_scalars' => [
                '0x4a3f2c1b5d6e',
                '0x7f8e9d0c1b2a'
             ],
            'pid'       => 11859,
            'runs'      => 16,
            'errors'    => 0,
            'interval'  => 5,
        },
        '1' => {
            'pid'           => 11860,
            'runs'          => 447,
            'errors'        => 2,
            'interval'      => 0.6,
            'error_message' => 'File notes.txt not found at scripts/write_file.pl line 227',
        }
    };

=head2 id

Returns the integer ID of the event.

=head2 info

Returns a hash reference containing a snapshot of the event's data. The
returned hash is a B<copy> — modifying it will not affect the live event.
C<shared_scalars> is an arrayref of hex key strings; use the scalar
reference returned by L</shared_scalar> to read or write values.

The snapshot is taken under a read lock (C<LOCK_SH>) for consistency.

    $VAR1 = {
        'shared_scalars' => [
            '0x4a3f2c1b5d6e',
            '0x7f8e9d0c1b2a'
         ],
        'pid'      => 6841,
        'runs'     => 4077,
        'errors'   => 0,
        'interval' => 1.4,
    };

=head2 pid

Returns the Process ID that the event is running under

=head2 runs

Returns the number of executions of the event's callback routine.

=head1 SCENARIOS/EXAMPLES

=head2 Run once

Send in an interval of zero (C<0>) to have your event run a single time. Call
C<start()> repeatedly for numerous individual/one-off runs.

    use Async::Event::Interval

    my $event = Async::Event::Interval->new(0, sub {print "hey\n";});

    $event->start;

    # Do stuff, then run the event again if it's done its previous task

    $event->start if $event->waiting;

=head2 Change delay interval during operation

Change the delay interval from 5 to 600 seconds after the event has fired 100
times

    use Async::Event::Interval

    my $event = Async::Event::Interval->new(5, sub {print "hey\n";});

    $event->start;

    while (1) {
        if ($event->runs > 99 && $event->interval != 600) {
            $event->interval(600);
        }

        #... do stuff
    }

=head2 Event error management

If an event crashes, print out error information and restart the event. If an
event crashes five or more times, print the most recent error message and halt
the program so you can figure out what's wrong with your callback code.

    use Async::Event::Interval

    my $event = Async::Event::Interval->new(5, sub {print "hey\n";});

    $event->start;

    while (1) {

        #... do stuff

        if ($event->errors >= 5) {
            print $event->error_message;
            exit;
        }

        if ($event->error) {
            printf(
                "Runs: %d, Runs errored: %d, Last error message: %s\n",
                $event->runs,
                $event->errors,
                $event->error_message;
            );

            $event->restart;
        }
    }

=head2 Event suicidal timeout

You can have your callback commit suicide if it takes too long to run. We use
Perl's C<$SIG{ALRM}> and C<alarm()> to do this. In your main application, you
can check the status of the event and restart it or whatever else you need.

    my $event_timeout = 30;

    my $event = Async::Event::Interval->new(
        30,
        sub {
            local $SIG{ALRM} = sub { print "Committing suicide!\n"; kill 9, $$; };

            alarm $event_timeout;

            # Do stuff here. If it takes 30 seconds, we kill ourselves

            alarm 0;
        },
    );

=head2 Per callback execution parameters

When using an event in a one-off situation where you restart the same event
manually, you can send in parameters that differ for each execution.

Send in a list of any data type. The list will be sent as-is to the callback.

NOTE: Parameters sent in to the C<start()> method will override ones sent into
the C<new()> method.

For example:

    use Async::Event::Interval

    my @params = (
        { a => 1 },
        { b => 2 },
        { c => 3 },
    );

    my $event = Async::Event::Interval->new(0, \&callback);

    my $count = 0;

    for my $href (@params) {
        $event->start($count, $href);
        while (! $event->waiting) {}
        $count++;
    }

    sub callback {
        my ($count, $href) = @_;
        my ($k, $v) = each %$href;
        print "$count: $k = $v\n";
    }

=head2 Global event callback parameters

You can send in a list of parameters to the event callback when instantiating
the event. Note that these parameters will remain the same for every call of
the callback.

Changing these within the main program will have no effect on the values sent
into the event itself. These parameter variables are copies and are not shared.
For shared variables, see L</shared_scalar>.

    use Async::Event::Interval

    my @params = qw(1 2 3);

    my $event = Async::Event::Interval->new(
        1,
        \&callback,
        @params
    );

    sub callback {
        my ($one, $two, $three) = @_;
        print "$one, $two, $three\n";
    }

=head2 Event crash: Restart event

    use warnings;
    use strict;

    use Async::Event::Interval;

    my $event = Async::Event::Interval->new(0.5, sub { kill 9, $$; });

    $event->start;

    sleep 1; # Do stuff

    if ($event->error){
        print "Event crashed, restarting\n";
        $event->restart;
    }

=head2 Event crash: End program

    use warnings;
    use strict;

    use Async::Event::Interval;

    my $event = Async::Event::Interval->new(0.5, sub { kill 9, $$; });

    $event->start;

    sleep 1; # Do stuff

    die "Event crashed, can't continue" if $event->error;

=head2 Shared data across events

This software uses L<IPC::Shareable> internally, so it's automatically
installed for you already. You can use shared data for use across many processes
and events, and if you use the same IPC key, even across multiple scripts.

Here's an example that uses a hash that's stored in shared memory, where the
parent process (the script) and two other processes (the two events) all share
and update the same hash.

    use Async::Event::Interval;
    use IPC::Shareable;

    tie my %shared_data, 'IPC::Shareable', {
        key         => '123456789',
        create      => 1,
        destroy     => 1
    };

    $shared_data{$$}{called_count}++;

    my $event_one = Async::Event::Interval->new(0.2, \&update);
    my $event_two = Async::Event::Interval->new(1, \&update);

    $event_one->start;
    $event_two->start;

    sleep 10;

    $event_one->stop;
    $event_two->stop;

    for my $pid (keys %shared_data) {
        printf(
            "Process ID %d executed %d times\n",
            $pid,
            $shared_data{$pid}{called_count}
        );
    }

    for my $event ($event_one, $event_two) {
        printf(
            "Event ID %d with PID %d ran %d times, with %d errors and an interval" .
            " of %.2f seconds\n",
            $event->id,
            $event->pid,
            $event->runs,
            $event->errors,
            $event->interval
        );
    }

    sub update {
        # Because each event runs in its own process, $$ will be set to the
        # process ID of the calling event, even though they both call this
        # same function

        $shared_data{$$}{called_count}++;
    }

=head1 AUTHOR

Steve Bertrand, C<< <steveb at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2024 Steve Bertrand.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.
