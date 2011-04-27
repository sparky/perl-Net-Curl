=head1 Curl::Transport

This module shows:

=over

=item buildtime version check

Required features will be missing if libcurl was too old at Net::Curl
compilation.

=item basic inheritance

Use Net::Curl::* as base for your modules.

=item exception handling

Most methods die() with a dualvar exception on error. You can compare them
numerically, or display as part of a message.

=back

=head2 Motivation

recv() and send() methods use non-blocking transfer, this may be very annoying
in simple scripts. This wrapper implements blocking send() wrapper, and two
recv() wrappers called read() and readline().

=head2 MODULE CODE

=cut
package Curl::Transport;

use strict;
use warnings;
use Net::Curl::Easy qw(/^CURLE_/);
use base qw(Net::Curl::Easy);

BEGIN {
	if ( Net::Curl::LIBCURL_VERSION_NUM() < 0x071202 ) {
		my $ver = Net::Curl::LIBCURL_VERSION();
		die "curl $ver does not support send() and recv()";
	}
	# alternatively you can write:
	if ( not Net::Curl::Easy->can( "send" )
			or not Net::Curl::Easy->can( "recv" ) ) {
		die "Net::Curl is missing send() and recv()\n"
	}
}

use constant {
	B_URI => 0,
	B_SOCKET => 1,
	B_VEC => 2,
	B_READBUF => 3,
};


# new( URL ) -- get new object
sub new
{
	my $class = shift;
	my $uri = shift;

	# use an array as our object base
	my $base = [ $uri, undef, undef, '' ];

	my $self = $class->SUPER::new( $base );

	$self->setopt( Net::Curl::Easy::CURLOPT_URL, $uri );
	$self->setopt( Net::Curl::Easy::CURLOPT_CONNECT_ONLY, 1 );

	# will die if fails
	$self->perform();

	$self->[ B_SOCKET ] = $self->getinfo(
		Net::Curl::Easy::CURLINFO_LASTSOCKET
	);

	# prepare select vector
	my $vec = '';
	vec( $vec, $self->[ B_SOCKET ], 1 ) = 1;
	$self->[ B_VEC ] = $vec;

	return $self;
}

# send( DATA ) -- send some data, wait for socket availability
# if it cannot be sent all at once
sub send($$)
{
	my $self = shift;
	my $data = shift;

	while ( length $data ) {
		# copy, because select overwrites those values
		my $w = $self->[ B_VEC ];

		# wait for write
		select undef, $w, undef, 0;

		# make sure some write bit is set
		next unless vec( $w, $self->[ B_SOCKET ], 1 );

		# actually send the data
		my $sent = $self->SUPER::send( $data );

		# remove from buffer what we sent
		substr $data, 0, $sent, '';
	};
}

# read( SIZE ) -- read SIZE bytes, wait for more data if there
# wasn't enough
sub read($$)
{
	my $self = shift;
	my $size = shift;

	return '' unless $size > 0;

	while ( length $self->[ B_READBUF ] < $size ) {
		my $r = $self->[ B_VEC ];

		# wait for data
		select $r, undef, undef, 0;

		# make sure some read bit is set
		redo unless vec( $r, $self->[ B_SOCKET ], 1 );

		eval {
			my $l = $self->SUPER::recv( $self->[ B_READBUF ],
				$size - length $self->[ B_READBUF ] );
		};
		if ( $@ ) {
			if ( $@ == CURLE_UNSUPPORTED_PROTOCOL ) {
				my $uri = $self->[ B_URI ];
				warn "Connection to $uri closed: $@\n";
				last;
			} elsif ( $@ == CURLE_AGAIN ) {
				warn "nothing to read, this should not happen";
			} else {
				die $@;
			}
		}
	}

	return substr $self->[ B_READBUF ], 0, $size, '';
}

# readline() -- read until $/
sub readline($)
{
	my $self = shift;

	# we allow changing $/, but we don't support $/ = undef.
	local $/;
	$/ = "\n" unless defined $/;

	my $idx;
	until ( ( $idx = index $self->[ B_READBUF ], $/ ) >= 0 ) {
		my $r = $self->[ B_VEC ];

		# wait for data
		select $r, undef, undef, 0;

		# make sure some read bit is set
		next unless vec( $r, $self->[ B_SOCKET ], 1 );

		# read 256 bytes, should be enough in most cases
		eval {
			$self->SUPER::recv( $self->[ B_READBUF ], 256 );
		};
		if ( $@ ) {
			if ( $@ == CURLE_UNSUPPORTED_PROTOCOL ) {
				my $uri = $self->[ B_URI ];
				warn "Connection to $uri closed: $@\n";
				last;
			} elsif ( $@ == CURLE_AGAIN ) {
				warn "nothing to read, this should not happen";
			} else {
				die $@;
			}
		}
	}

	return substr $self->[ B_READBUF ], 0, ($idx + length $/), '';
}

1;

=head2 TEST APPLICATION

Sample application using this module could look like this:

	#!perl
	use strict;
	use warnings;
	use Curl::Transport;
#nopod
=cut
package main;

use strict;
use warnings;
#endnopod

my $host = shift @ARGV || "example.com";

my $t = Curl::Transport->new( "http://$host" );
$t->send( "GET / HTTP/1.0\r\n" );
$t->send( "User-Agent: Curl::Transport test\r\n" );
$t->send( "Accept: */*\r\n" );
$t->send( "Host: $host\r\n" );
$t->send( "Connection: Close\r\n" );
$t->send( "\r\n" );

my $length;
{
	local $/ = "\r\n";
	local $_;
	do {
		$_ = $t->readline();
		$length = 0 | $1 if /Content-Length:\s*(\d+)/;
		chomp;
		print "HEADER: $_\n";
	} while ( length $_ );
}

if ( defined $length ) {
	print "Reading $length bytes of data:\n";
	print $t->read( $length );

	print "\nTrying to read one more byte, should fail:\n";
	print $t->read( 1 );
	print "\n";
} else {
	print "Don't know how much to read\n";
	while ( $_ = $t->readline() ) {
		print;
	}
}

printf "Last error: %s\n", $t->error();
#nopod
# vim: ts=4:sw=4
