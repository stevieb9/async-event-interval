package Async::Event::Interval;

use warnings;
use strict;

our $VERSION = '0.01';

use Parallel::ForkManager;

my $continue = 1;

$SIG{INT} = sub {
    $continue = 0;
};

sub new {
    my $self = bless {}, shift;
    $self->{pm} = Parallel::ForkManager->new(1);
    $self->event(@_);
    return $self;
}
sub event {
    my $self = shift;
    $self->_set(@_);

    for (0..1){
        my $pid = $self->{pm}->start;
        if ($pid){
           $self->_pid($pid);
           last;
        }
        while($continue){
            $self->{cb}->(@{ $self->{args} });
            sleep $self->{interval};
        }
        $self->{pm}->finish;
    }
}
sub restart {
    my $self = shift;
    $self->event(
        $self->{interval},
        $self->{cb},
        @{ $self->{args} },
    );
}
sub stop {
    kill 9 => $_[0]->{pid};
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

Async::Event::Interval - The great new Async::Event::Interval!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Async::Event::Interval;

    my $foo = Async::Event::Interval->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub function1 {
}

=head2 function2

=cut

sub function2 {
}

=head1 AUTHOR

Steve Bertrand, C<< <steveb at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-fork-event-interval at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Fork-Event-Interval>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Async::Event::Interval


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Fork-Event-Interval>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Fork-Event-Interval>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Fork-Event-Interval>

=item * Search CPAN

L<http://search.cpan.org/dist/Fork-Event-Interval/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2016 Steve Bertrand.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.


=cut

1; # End of Async::Event::Interval
