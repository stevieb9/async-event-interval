package Async::Event::Interval;

use warnings;
use strict;

our $VERSION = '1.03';

use Carp qw(croak);
use IPC::Shareable;
use Parallel::ForkManager;

$SIG{CHLD} = "IGNORE";
$SIG{__WARN__} = sub {
    my $warn = shift;
    warn $warn if $warn !~ /^child process/;
};

my $id = 0;
my %events;

*restart = \&start;

sub new {
    my $self = bless {}, shift;
    $self->_pm;
    $self->_set(@_);
    $self->{started} = 0;

    $self->{id} = $id;
    $id++;
    $events{$self->id} = {};

    return $self;
}
sub events {
    return \%events;
}
sub id {
    return $_[0]->{id};
}
sub info {
    my ($self) = @_;
    return $self->events()->{$self->id};
}
sub shared_scalar {
    my ($self) = @_;

    my $shm_key = _rand_shm_key();

    tie my $scalar, 'IPC::Shareable', $shm_key, {create => 1, destroy => 1};

    $events{$self->id}->{shared_scalars}{$shm_key} = \$scalar;

    return \$scalar;
}
sub start {
    my $self = shift;
    if ($self->{started}){
        warn "Event already running...\n";
        return;
    }
    $self->{started} = 1;
    $self->_event;
}
sub status {
    my $self = shift;

    if ($self->{started}){
        if (! $self->_pid){
            croak "Event is started, but no PID can be found. This is a " .
                "fatal error. Exiting...\n";
        }
        if ($self->_pid > 0){
            if (kill 0, $self->_pid){
                return $self->_pid;
            }
            else {
                # proc must have crashed
                $self->{started} = 0;
                $self->_pid(-99);
                return -1;
            }
        }
    }
    return -1 if defined $self->_pid && $self->_pid == -99;
    return 0;
}
sub stop {
    my $self = shift;

    if ($self->_pid){
        kill 9, $self->_pid;

        $self->{started} = 0;
        $self->{stop} = 1;

        # time to ensure the proc was killed

        sleep 1;

        if (kill 0, $self->_pid){
            croak "Event stop was called, but the process hasn't been killed. " .
                  "This is a fatal event. Exiting...\n";
        }
    }
}
sub waiting {
    my ($self) = @_;
    return 1 if ! $self->status || $self->status == -1;
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
        die "Callback must be a code reference." if ref $cb ne 'CODE';
        $self->{cb} = $cb;
    }

    return $self->{cb};
}
sub _event {
    my $self = shift;
    
    for (0..1){
        my $pid = $self->_pm->start;
        if ($pid){
            # this is the parent process
            $self->_pid($pid);
            last;
        }

        # set the child's proc id

        $self->_pid($$);

        # if no interval, run only once

        if ($self->_interval) {
            while (1) {
                $self->_cb->(@{$self->_args});
                select(undef, undef, undef, $self->_interval);
            }
        }
        else {
            $self->_cb->(@{$self->_args});
        }

        $self->_pm->finish;
    }
}
sub _interval {
    my ($self, $interval) = @_;

    if (defined $interval) {
        $self->{interval} = $interval;
    }

    return $self->{interval};
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
    $self->{pid} = $pid if defined $pid;
    $events{$self->id}->{pid} = $self->{pid};
    return $self->{pid} || undef;
}
sub _rand_shm_key {
    my $key_str;

    for (0..3) {
        $key_str .= ('A'..'Z')[rand(26)];
    }

   return $key_str;
}
sub _set {
    my ($self, $interval, $cb, @args) = @_;
    $self->_interval($interval);
    $self->_cb($cb);
    $self->_args(\@args);
}

sub DESTROY {
    $_[0]->stop if $_[0]->_pid;
}
sub _vim{}

1;

__END__

=head1 NAME

Async::Event::Interval - Timed and one-off asynchronous events

=for html
<a href="https://github.com/stevieb9/async-event-interval/actions"><img src="https://github.com/stevieb9/async-event-interval/workflows/CI/badge.svg"/></a>
<a href='https://coveralls.io/github/stevieb9/async-event-interval?branch=master'><img src='https://coveralls.io/repos/stevieb9/async-event-interval/badge.svg?branch=master&service=github' alt='Coverage Status' /></a>


=head1 SYNOPSIS

A simple event that updates JSON data from a website while allowing the main
application to continue running in the foreground. Multiple events can be
simultaneously used.

See L</EXAMPLES> for other various functionality of this module.

    use warnings;
    use strict;

    use Async::Event::Interval;

    my $event = Async::Event::Interval->new(2, \&callback);

    my $shared_scalar_json      = $event->shared_scalar;

    $event->start;

    while (1) {
        print "$$shared_scalar_json\n";

        if ($event->status == -1) {
            # Event crashed
            $event->restart;
        }
    }

    sub callback {
        my $json = ...; # Fetch JSON from a website

        if ($json) {
            $$shared_scalar_json = $json;
        }
    }

=head1 DESCRIPTION

Very basic implementation of asynchronous events that are triggered by a timed
interval. If no time is specified, we'll run the event only once.

Variables are not shared between the main application and the event. To do that,
you'll need to use some form of memory sharing, such as L<IPC::Shareable>. See
L</EXAMPLES> for an example. At this time, there is no real parameter passing or
ability to return values. As I said... basic.

Each event is simply a separate forked process, which runs in a while loop.

=head1 METHODS

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
code will not be seen in the event, and vice-versa.

=head2 start

Starts the event timer. Each time the interval is reached, the event callback
is executed.

=head2 stop

Stops the event from being executed.

=head2 restart

Alias for C<start()>. Re-starts a C<stop()>ped event.

=head2 status

Returns the event's process ID (true) if it is running, C<0> (false) if it
isn't, and C<-1> if the event has crashed.

=head2 waiting

Returns true if the event is dormant and is ready for a C<start()> or C<restart>
command. Returns false if the event is already running.

=head2 shared_scalar

Returns a reference to a scalar variable that can be shared between the main
process and the events. This reference can be used within multiple events, and
multiple shared scalars can be created by each event.

To read from or assign to the returned scalar, you must dereference it:
C<$$shared_scalar = 1;>.

=head2 id

Returns the integer ID of the event.

=head2 info

Returns a hash reference containing various data about the event. Eg.

    $VAR1 = {
        'shared_scalars' => {
            '0x55435449' => \'hello, world!,
            '0x43534644' => \98
         },
        'pid' => 6841,
    };

=head2 events

This is a class method that returns a hash reference that contains the data of
all existing events. Call it with C<Async::Event::Interval::events()>.

    $VAR1 = {
        '0' => {
            'shared_scalars' => {
                '0x555A4654' => \'hello, world',
                '0x4C534758' => \98
             },
            'pid' => 11859,
        },
        '1' => {
            'pid' => 11860
        }
    };

=head1 EXAMPLES

=head2 Run Once

Send in an interval of zero (C<0>) to have your event run a single time. Call
C<start()> repeatedly for numerous runs.

    use Async::Event::Interval

    my $event = Async::Event::Interval->new(0, sub {print "hey\n";});

    $event->start;

    # Do stuff, then run the event again if it's done its previous task

    $event->start if $event->waiting;

=head2 Event Parameters

You can send in a list of parameters to the event callback. Changing these
within the main program will have no effect on the values sent into the
event itself.

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
    use feature 'say';

    use Async::Event::Interval;

    my $event = Async::Event::Interval->new(
        2,
        sub {
            kill 9, $$;
        },
    );

    $event->start;

    sleep 1; # do stuff

    if ($event->status == -1){
        say "event crashed, restarting";
        $event->restart;
    }

=head2 Event crash: End program

    use warnings;
    use strict;
    use feature 'say';

    use Async::Event::Interval;

    my $event = Async::Event::Interval->new(
        2,
        sub {
            kill 9, $$;
        },
    );

    $event->start;

    sleep 1; # do stuff

    if ($event->status == -1){
        say "event crashed, can't continue...";
        exit;
    }

=head1 AUTHOR

Steve Bertrand, C<< <steveb at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2021 Steve Bertrand.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.
