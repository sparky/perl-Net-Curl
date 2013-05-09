package WWW::Curl::Easy;

use strict;
use warnings;
use WWW::Curl ();
use Net::Curl::Easy ();
use Exporter ();
our @ISA = qw(Net::Curl::Easy Exporter);

our $VERSION = 4.15;
our @EXPORT;

BEGIN {
	# in WWW::Curl almost all the constants are thrown into WWW::Curl::Easy
	foreach my $pkg ( qw(Net::Curl:: Net::Curl::Easy::
			Net::Curl::Form:: Net::Curl::Share::
			Net::Curl::Multi::) ) {
		WWW::Curl::_copy_constants(
			\@EXPORT, __PACKAGE__, $pkg );
	}
}

# what is that anyways ?
$WWW::Curl::Easy::headers = "";
$WWW::Curl::Easy::content = "";

sub new
{
	my $class = shift || __PACKAGE__;
	return $class->SUPER::new();
}

*init = \&new;
*errbuf = \&Net::Curl::Easy::error;
*strerror = \&Net::Curl::Easy::strerror;

*version = \&Net::Curl::version;

sub cleanup { 0 };

sub internal_setopt { die };

sub duphandle
{
	my ( $source ) = @_;
	my $clone = $source->SUPER::duphandle;
	bless $clone, "WWW::Curl::Easy"
}

sub const_string
{
	my ( $self, $constant ) = @_;
	return constant( $constant );
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
	# convert options and provide wrappers for callbacks
	my ($self, $option, $value, $push) = @_;

	if ( $push ) {
		return $self->pushopt( $option, $value );
	}

	if ( $option == CURLOPT_PRIVATE ) {
		# stringified
		$self->{private} = "$value";
		return 0;
	} elsif ( $option == CURLOPT_ERRORBUFFER ) {
		# I don't even know how was that supposed to work, but it does
		$self->{errorbuffer} = $value;
		return 0;
	}

	# wrappers for callbacks
	if ( $option == CURLOPT_WRITEFUNCTION ) {
		my $sub = $value;
		$value = sub {
			my ( $easy, $data, $uservar ) = @_;
			return $sub->( $data, $uservar );
		};
	} elsif ( $option == CURLOPT_HEADERFUNCTION ) {
		my $sub = $value;
		$value = sub {
			my ( $easy, $data, $uservar ) = @_;
			return $sub->( $data, $uservar );
		};
	} elsif ( $option == CURLOPT_READFUNCTION ) {
		my $sub = $value;
		$value = sub {
			my ( $easy, $maxlen, $uservar ) = @_;
			return \( $sub->( $maxlen, $uservar ) );
		};
	} elsif ( $option == CURLOPT_PROGRESSFUNCTION ) {
		my $sub = $value;
		$value = sub {
			my ( $easy, $dltotal, $dlnow, $ultotal, $ulnow, $uservar ) = @_;
			return $sub->( $uservar, $dltotal, $dlnow, $ultotal, $ulnow );
		};
	} elsif ( $option == CURLOPT_DEBUGFUNCTION ) {
		my $sub = $value;
		$value = sub {
			my ( $easy, $type, $data, $uservar ) = @_;
			return $sub->( $data, $uservar, $type );
		};
	}
	eval {
		$self->SUPER::setopt( $option, $value );
	};
	return 0 unless $@;
	return 0+$@ if ref $@ eq "Net::Curl::Easy::Code";
	die $@;
}

sub pushopt
{
	my ($self, $option, $value) = @_;
	eval {
		$self->SUPER::pushopt( $option, $value );
	};
	return 0 unless $@;
	if ( ref $@ eq "Net::Curl::Easy::Code" ) {
		# WWW::Curl allows to use pushopt on non-slist arguments
		if ( $@ == CURLE_BAD_FUNCTION_ARGUMENT ) {
			return $self->setopt( $option, $value );
		}
		return 0+$@;
	}
	die $@;
}

sub getinfo
{
	my ($self, $option) = @_;

	my $ret;
	if ( $option == CURLINFO_PRIVATE ) {
		$ret = $self->{private};
	} else {
		eval {
			$ret = $self->SUPER::getinfo( $option );
		};
		if ( $@ ) {
			return undef if ref $@ eq "Net::Curl::Easy::Code";
			die $@;
		}
	}
	if ( @_ > 2 ) {
		$_[2] = $ret;
	}
	return $ret;
}

sub perform
{
	my $self = shift;
	eval {
		$self->SUPER::perform( @_ );
	};
	if ( defined $self->{errorbuffer} ) {
		my $error = $self->error();

		no strict 'refs';

		# copy error message to specified global variable
		# not really sure where that should go
		*{ "main::" . $self->{errorbuffer} } = \$error;
		*{ "::" . $self->{errorbuffer} } = \$error;
		*{ $self->{errorbuffer} } = \$error;
	}
	return 0 unless $@;
	return 0+$@ if ref $@ eq "Net::Curl::Easy::Code";
	die $@;
}

1;
