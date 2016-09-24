package Async::Event::Interval;

use warnings;
use strict;

our $VERSION = '0.01';

use Parallel::ForkManager;

sub new {
    my $self = bless {}, shift;
    $self->{pm} = Parallel::ForkManager->new(1);
    $self->_set(@_);
    return $self;
}

sub start {
    my $self = shift;
    if ($self->{stop}){
        warn "event already running...\n";
        return;
    }
    $self->_event;
}
sub restart {
    my $self = shift;
    if ($self->{stop}){
        warn "event already running...\n";
        return;
    }
    $self->_event(
        $self->{interval},
        $self->{cb},
        @{ $self->{args} },
    );
}
sub stop {
    my $self = shift;
    kill 9, $self->{pid};
    $self->{stop} = 1;
}
sub _event {
    my $self = shift;

    for (0..1){
        my $pid = $self->{pm}->start;
        if ($pid){
           $self->_pid($pid);
           last;
        }
        while(1){
            $self->{cb}->(@{ $self->{args} });
            sleep $self->{interval};
        }
        $self->{pm}->finish;
    }
}
sub _pid {
    my ($self, $pid) = @_;
    $self->{pid} = $pid if defined $pid;
    return $self->{pid} || undef;
}
sub _set {
    my ($self, $interval, $cb, @args) = @_;
    $self->{interval} = $interval;
    $self->{cb} = $cb;
    $self->{args} = \@args;
}
sub DESTROY {
    $_[0]->stop;
}
1;

__END__

=head1 NAME

Async::Event::Interval - Extremely simple timed asynchronous events

=head1 SYNOPSIS

A simple event. Multiple events can be simultaneously used. For an example using
an event that can share data with the main application, see L<EXAMPLES>.

    use Async::Event::Interval;

    my $event
        = Async::Event::Interval->new(1.5, \&callback);

    $event->start;

    for (1..10){
        print "$_: in main loop\n";

        $event->stop if $_ == 3;
        $event->restart if $_ == 7;

        sleep 1;
    }

    sub callback {
        print "timed event callback\n";
    }

=head1 DESCRIPTION

Very basic implementation of asynchronous events that are triggered by a timed
interval.

Variables are not shared between the main application and the event. To do that,
you'll need to use some form of memory sharing, such as L<IPC::Shareable>. See
L<EXAMPLES> for an example.

Each event is simply a separate forked process, which runs in a while loop.

=head1 METHODS

=head2 new($delay, $callback)

Returns a new C<Async::Event::Interval> object. Does not create the event. Use
C<start> for that.

Parameters:

    $delay

Mandatory: The interval on which to trigger your event callback, in seconds.
Represent partial seconds as a floating point number.

    $callback

Mandatory: A reference to a subroutine that will be called every time the
interval expires.

=head2 start

Starts the event timer. Each time the interval is reached, the event callback
is executed.

=head2 stop

Stops the event from being executed.

=head2 restart

Resumes execution of a stopped event.

=head1 EXAMPLES

A timed event where the event callback shares a hash reference with the main
program.

    use Async::Event::Interval;
    use IPC::Shareable;

    my $href = {a => 0, b => 1};
    tie $href, 'IPC::Shareable', undef;

    my $event
        = Async::Event::Interval->new(10, \&callback);

    sub callback {
        $h->{a}++;
    }

=head1 AUTHOR

Steve Bertrand, C<< <steveb at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2016 Steve Bertrand.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.
