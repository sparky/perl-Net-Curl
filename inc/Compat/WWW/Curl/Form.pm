package WWW::Curl::Form;

use strict;
use warnings;
use WWW::Curl ();
use Net::Curl::Form ();
use Exporter ();
our @ISA = qw(Net::Curl::Form Exporter);

our $VERSION = 4.15;

our @EXPORT;

BEGIN {
	WWW::Curl::_copy_constants(
		\@EXPORT, __PACKAGE__, "Net::Curl::Form::" );
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

sub new
{
	my $class = shift || __PACKAGE__;
	return $class->SUPER::new();
}

sub formadd
{
	my ( $self, $name, $value ) = @_;
	eval {
		$self->add(
			CURLFORM_COPYNAME, $name,
			CURLFORM_COPYCONTENTS, $value
		);
	};
}

sub formaddfile
{
	my ( $self, $filename, $description, $type ) = @_;
	eval {
		$self->add(
			CURLFORM_FILE, $filename,
			CURLFORM_COPYNAME, $description,
			CURLFORM_CONTENTTYPE, $type,
		);
	};
}

1;
