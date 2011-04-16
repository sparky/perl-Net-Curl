package WWW::CurlOO::Compat;
=head1 NAME

WWW::CurlOO::Compat -- compatibility layer for WWW::Curl

=head1 SYNOPSIS

 --- old.pl
 +++ new.pl
 @@ -2,6 +2,8 @@
  use strict;
  use warnings;

 +# support both WWW::CurlOO (default) and WWW::Curl
 +BEGIN { eval { require WWW::CurlOO::Compat; } }
  use WWW::Curl::Easy 4.15;
  use WWW::Curl::Multi;

=head1 DESCRIPTION

WWW::CurlOO::Compat lets you use WWW::CurlOO in applications and modules
that normally use WWW::Curl. There are several ways to accomplish it:

=head2 EXECUTION

Execute an application through perl with C<-MWWW::CurlOO::Compat> argument:

 perl -MWWW::CurlOO::Compat APPLICATION [ARGUMENTS]

=head2 CODE, use WWW::CurlOO by default

Add this line before including any WWW::Curl modules:

 BEGIN { eval { require WWW::CurlOO::Compat; } }

This will try to preload WWW::CurlOO, but won't fail if it isn't available.

=head2 CODE, use WWW::Curl by default

Add those lines before all the others that use WWW::Curl:

 BEGIN {
     eval { require WWW::Curl; }
     require WWW::CurlOO::Compat if $@;
 }

This will try WWW::Curl first, but will fallback to WWW::CurlOO if that fails.

=head1 NOTE

If you want to write compatible code, DO NOT USE WWW::CurlOO::Compat during
development. This module hides all the incompatibilities, but does not disable
any of the features that are unique to WWW::CurlOO. You could end up using
methods that do not yet form part of official WWW::Curl distribution.

=cut

use strict;
use warnings;

my @packages = qw(
	WWW/Curl.pm
	WWW/Curl/Easy.pm
	WWW/Curl/Form.pm
	WWW/Curl/Multi.pm
	WWW/Curl/Share.pm
);

# mark fake packages as loaded
@INC{ @packages } = ("WWW::CurlOO::Compat") x scalar @packages;

# copies constants to current namespace
sub _copy_constants
{
	my $EXPORT = shift;
	my $dest = shift;
	my $source = shift;

	no strict 'refs';
	my @constants = grep /^CURL/, keys %{ "$source" };
	push @$EXPORT, @constants;

	foreach my $name ( @constants ) {
		*{ $dest . $name } = \*{ $source . $name};
	}
}



use WWW::CurlOO ();
use WWW::CurlOO::Easy qw(/^CURLOPT_/ CURLE_BAD_FUNCTION_ARGUMENT CURLINFO_PRIVATE);
use WWW::CurlOO::Form qw(/^CURLFORM_/);
use WWW::CurlOO::Share ();
use WWW::CurlOO::Multi ();
use Exporter ();

# WWW::Curl

$WWW::Curl::VERSION = '4.15';


# WWW::Curl::Easy

@WWW::Curl::Easy::ISA = qw(WWW::CurlOO::Easy Exporter);
$WWW::Curl::Easy::VERSION = '4.15';

BEGIN {
	my $e = [];
	# in WWW::Curl almost all the constants are thrown into WWW::Curl::Easy
	foreach my $pkg ( qw(WWW::CurlOO:: WWW::CurlOO::Easy::
			WWW::CurlOO::Form:: WWW::CurlOO::Share::
			WWW::CurlOO::Multi::) ) {
		WWW::CurlOO::Compat::_copy_constants(
			$e, 'WWW::Curl::Easy::', $pkg );
	}
	@WWW::Curl::Easy::EXPORT = @$e;
}

# what is that anyways ?
$WWW::Curl::Easy::headers = "";
$WWW::Curl::Easy::content = "";

sub WWW::Curl::Easy::new
{
	my $class = shift || 'WWW::Curl::Easy';
	return WWW::CurlOO::Easy::new( $class );
}

*WWW::Curl::Easy::init = \&WWW::Curl::Easy::new;
*WWW::Curl::Easy::errbuf = \&WWW::CurlOO::Easy::error;
*WWW::Curl::Easy::strerror = \&WWW::CurlOO::Easy::strerror;

*WWW::Curl::Easy::version = \&WWW::CurlOO::version;

sub WWW::Curl::Easy::cleanup { 0 };

sub WWW::Curl::Easy::internal_setopt { die };

sub WWW::Curl::Easy::duphandle
{
	my ( $source ) = @_;
	my $clone = WWW::CurlOO::Easy::duphandle( $source );
	bless $clone, "WWW::Curl::Easy"
}

sub WWW::Curl::Easy::const_string
{
	my ( $self, $constant ) = @_;
	return WWW::Curl::Easy::constant( $constant );
}

# this thing is weird !
sub WWW::Curl::Easy::constant
{
	my $name = shift;
	undef $!;
	my $value = eval "WWW::Curl::Easy::$name()";
	if ( $@ ) {
		require POSIX;
		$! = POSIX::EINVAL();
		return undef;
	}
	return $value;
}

sub WWW::Curl::Easy::setopt
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
		WWW::CurlOO::Easy::setopt( $self, $option, $value );
	};
	return 0 unless $@;
	return 0+$@ if ref $@ eq "WWW::CurlOO::Easy::Code";
	die $@;
}

sub WWW::Curl::Easy::pushopt
{
	my ($self, $option, $value) = @_;
	eval {
		WWW::CurlOO::Easy::pushopt( $self, $option, $value );
	};
	return 0 unless $@;
	if ( ref $@ eq "WWW::CurlOO::Easy::Code" ) {
		# WWW::Curl allows to use pushopt on non-slist arguments
		if ( $@ == CURLE_BAD_FUNCTION_ARGUMENT ) {
			return $self->setopt( $option, $value );
		}
		return 0+$@;
	}
	die $@;
}

sub WWW::Curl::Easy::getinfo
{
	my ($self, $option) = @_;

	my $ret;
	if ( $option == CURLINFO_PRIVATE ) {
		$ret = $self->{private};
	} else {
		eval {
			$ret = WWW::CurlOO::Easy::getinfo( $self, $option );
		};
		if ( $@ ) {
			return undef if ref $@ eq "WWW::CurlOO::Easy::Code";
			die $@;
		}
	}
	if ( @_ > 2 ) {
		$_[2] = $ret;
	}
	return $ret;
}

sub WWW::Curl::Easy::perform
{
	my $self = shift;
	eval {
		WWW::CurlOO::Easy::perform( $self );
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
	return 0+$@ if ref $@ eq "WWW::CurlOO::Easy::Code";
	die $@;
}


# WWW::Curl::Form

@WWW::Curl::Form::ISA = qw(WWW::CurlOO::Form Exporter);
$WWW::Curl::Form::VERSION = '4.15';

BEGIN {
	@WWW::Curl::Form::EXPORT = ();
	WWW::CurlOO::Compat::_copy_constants(
		\@WWW::Curl::Form::EXPORT, 'WWW::Curl::Form::',
		"WWW::CurlOO::Form::" );
}

# this thing is weird !
sub WWW::Curl::Form::constant
{
	my $name = shift;
	undef $!;
	my $value = eval "WWW::Curl::Form::$name()";
	if ( $@ ) {
		require POSIX;
		$! = POSIX::EINVAL();
		return undef;
	}
	return $value;
}

sub WWW::Curl::Form::new
{
	my $class = shift || 'WWW::Curl::Form';
	return WWW::CurlOO::Form::new( $class );
}

sub WWW::Curl::Form::formadd
{
	my ( $self, $name, $value ) = @_;
	eval {
		$self->add(
			CURLFORM_COPYNAME, $name,
			CURLFORM_COPYCONTENTS, $value
		);
	};
}

sub WWW::Curl::Form::formaddfile
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


# WWW::Curl::Multi

@WWW::Curl::Multi::ISA = qw(WWW::CurlOO::Multi);

*WWW::Curl::Multi::strerror = \&WWW::CurlOO::Multi::strerror;

sub WWW::Curl::Multi::new
{
	my $class = shift || 'WWW::Curl::Multi';
	return WWW::CurlOO::Multi::new( $class );
}

sub WWW::Curl::Multi::add_handle
{
	my ( $multi, $easy ) = @_;
	eval {
		WWW::CurlOO::Multi::add_handle( $multi, $easy );
	};
}

sub WWW::Curl::Multi::remove_handle
{
	my ( $multi, $easy ) = @_;
	eval {
		WWW::CurlOO::Multi::remove_handle( $multi, $easy );
	};
}

sub WWW::Curl::Multi::info_read
{
	my ( $multi ) = @_;
	my @ret;
	eval {
		@ret = WWW::CurlOO::Multi::info_read( $multi );
	};
	return () unless @ret;

	my ( $msg, $easy, $result ) = @ret;
	$multi->remove_handle( $easy );

	return ( $easy->{private}, $result );
}

sub WWW::Curl::Multi::fdset
{
	my ( $multi ) = @_;
	my @vec;
	eval {
		@vec = WWW::CurlOO::Multi::fdset( $multi );
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

sub WWW::Curl::Multi::perform
{
	my ( $multi ) = @_;

	my $ret;
	eval {
		$ret = WWW::CurlOO::Multi::perform( $multi );
	};

	return $ret;
}

# WWW::Curl::Share

@WWW::Curl::Share::ISA = qw(WWW::CurlOO::Share Exporter);

BEGIN {
	@WWW::Curl::Share::EXPORT = ();
	WWW::CurlOO::Compat::_copy_constants(
		\@WWW::Curl::Share::EXPORT, 'WWW::Curl::Share::',
		"WWW::CurlOO::Share::" );
}

*WWW::Curl::Share::strerror = \&WWW::CurlOO::Share::strerror;

sub WWW::Curl::Share::new
{
	my $class = shift || 'WWW::Curl::Share';
	return WWW::CurlOO::Share::new( $class );
}

# this thing is weird !
sub WWW::Curl::Share::constant
{
	my $name = shift;
	undef $!;
	my $value = eval "WWW::Curl::Share::$name()";
	if ( $@ ) {
		require POSIX;
		$! = POSIX::EINVAL();
		return undef;
	}
	return $value;
}

sub WWW::Curl::Share::setopt
{
	my ($self, $option, $value) = @_;
	eval {
		WWW::CurlOO::Share::setopt( $self, $option, $value );
	};
	return 0 unless $@;
	return 0+$@ if ref $@ eq "WWW::CurlOO::Form::Code";
	die $@;
}

1;

=head1 COPYRIGHT

Copyright (c) 2011 Przemyslaw Iskra <sparky at pld-linux.org>.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.
