package WWW::Curl::Share;

use strict;
use warnings;
use WWW::Curl ();
use Net::Curl::Share ();
use Exporter ();
our @ISA = qw(Net::Curl::Share Exporter);

our @EXPORT;

BEGIN {
	WWW::Curl::_copy_constants(
		\@EXPORT, __PACKAGE__, "Net::Curl::Share::" );
}

*strerror = \&Net::Curl::Share::strerror;

sub new
{
	my $class = shift || __PACKAGE__;
	return $class->SUPER::new();
}

# this thing is weird !
sub constant
{
	my $name = shift;
	undef $!;
	my $value = eval "$name()";
	if ( $@ ) {
		require POSIX;
		$! = POSIX::EINVAL();
		return undef;
	}
	return $value;
}

sub setopt
{
	my ($self, $option, $value) = @_;
	eval {
		$self->SUPER::setopt( $option, $value );
	};
	return 0 unless $@;
	return 0+$@ if ref $@ eq "Net::Curl::Share::Code";
	die $@;
}

1;
