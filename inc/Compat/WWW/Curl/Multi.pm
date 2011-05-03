package WWW::Curl::Multi;

use strict;
use warnings;
use WWW::Curl ();
use Net::Curl::Multi ();
our @ISA = qw(Net::Curl::Multi);

*strerror = \&Net::Curl::Multi::strerror;

sub new
{
	my $class = shift || __PACKAGE__;
	return $class->SUPER::new();
}

sub add_handle
{
	my ( $multi, $easy ) = @_;
	eval {
		$multi->SUPER::add_handle( $easy );
	};
}

sub remove_handle
{
	my ( $multi, $easy ) = @_;
	eval {
		$multi->SUPER::remove_handle( $easy );
	};
}

sub info_read
{
	my ( $multi ) = @_;
	my @ret;
	eval {
		@ret = $multi->SUPER::info_read();
	};
	return () unless @ret;

	my ( $msg, $easy, $result ) = @ret;
	$multi->remove_handle( $easy );

	return ( $easy->{private}, $result );
}

sub fdset
{
	my ( $multi ) = @_;
	my @vec;
	eval {
		@vec = $multi->SUPER::fdset;
	};
	my @out;
	foreach my $in ( @vec ) {
		my $max = 8 * length $in;
		my @o;
		foreach my $fn ( 0..$max ) {
			push @o, $fn if vec $in, $fn, 1;
		}
		push @out, \@o;
	}

	return @out;
}

sub perform
{
	my ( $multi ) = @_;

	my $ret;
	eval {
		$ret = $multi->SUPER::perform;
	};

	return $ret;
}

1;
