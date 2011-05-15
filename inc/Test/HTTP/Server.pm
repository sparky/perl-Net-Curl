package Test::HTTP::Server;
#
# 2011 (c) Przemysław Iskra <sparky@pld-linux.org>
#		This program is free software,
# you may distribute it under the same terms as Perl.
#
use strict;
use warnings;
use IO::Socket;
use POSIX ":sys_wait_h";

our $VERSION = '0.03';

sub _open_socket
{
	my $frompid = $$;
	$frompid %= 63 * 1024;
	$frompid += 63 * 1024 if $frompid < 1024;
	my $port = $ENV{HTTP_PORT} || $frompid;
	foreach ( 0..100 ) {
		my $socket = IO::Socket::INET->new(
			Proto => 'tcp',
			LocalPort => $port,
			Listen => 5,
			Reuse => 1,
			Blocking => 1,
		);
		return ( $port, $socket ) if $socket;
		$port = 1024 + int rand 63 * 1024;
	}
}

sub new
{
	my $class = shift;

	my ( $port, $socket ) = _open_socket()
		or die "Could not start HTTP server\n";

	my $pid = fork;
	die "Could not fork\n"
		unless defined $pid;
	if ( $pid ) {
		my $self = {
			address => "127.0.0.1",
			port => $port,
			pid => $pid,
		};
		return bless $self, $class;
	} else {
		$SIG{CHLD} = \&_sigchld;
		_main_loop( $socket, @_ );
		exec "true";
		die "Should not be here\n";
	}
}

sub uri
{
	my $self = shift;
	return "http://$self->{address}:$self->{port}/";
}

sub port
{
	my $self = shift;
	$self->{port};
}

sub address
{
	my $self = shift;
	if ( @_ ) {
		$self->{address} = shift;
	}
	$self->{address};
}

sub _sigchld
{
	my $kid;
	local $?;
	do {
		$kid = waitpid -1, WNOHANG;
	} while ( $kid > 0 );
}

sub DESTROY
{
	my $self = shift;
	my $done = 0;
	local $SIG{CHLD} = \&_sigchld;
	my $cnt = kill 15, $self->{pid};
	return unless $cnt;
	foreach my $sig ( 15, 15, 15, 9, 9, 9 ) {
		$cnt = kill $sig, $self->{pid};
		last unless $cnt;
		select undef, undef, undef, 0.1;
	}
}

sub _term
{
	exec "true";
	die "Should not be here\n";
}

sub _main_loop
{
	my $socket = shift;
	$SIG{TERM} = \&_term;

	for (;;) {
		my $client = $socket->accept()
			or redo;
		my $pid = fork;
		die "Could not fork\n" unless defined $pid;
		if ( $pid ) {
			close $client;
		} else {
			Test::HTTP::Server::Request->open( $client, @_ );
			_term();
		}
	}
}

package Test::HTTP::Server::Connection;

BEGIN {
	eval {
		require URI::Escape;
		URI::Escape->import( qw(uri_unescape) );
	};
	if ( $@ ) {
		*uri_unescape = sub {
			local $_ = shift;
			s/%(..)/chr hex $1/eg;
			return $_;
		};
	}
}

use constant DNAME => [qw(Sun Mon Tue Wed Thu Fri Sat)];
use constant MNAME => [qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)];

sub _http_time
{
	my $self = shift;
	my @t = gmtime( shift || time );
	return sprintf '%s, %02d %s %04d %02d:%02d:%02d GMT',
		DNAME->[ $t[6] ], $t[3], MNAME->[ $t[4] ], 1900+$t[5],
		$t[2], $t[1], $t[0];
}

sub open
{
	my $class = shift;
	my $socket = shift;

	open STDOUT, '>&', $socket;
	open STDIN, '<&', $socket;

	my $self = {
		version => "1.0",
		@_,
		socket => $socket,
	};
	bless $self, $class;
	$self->process;
}

sub process
{
	my $self = shift;
	$self->in_all;
	$self->out_all;
	close STDIN;
	close STDOUT;
	close $self->{socket};
}

sub in_all
{
	my $self = shift;
	$self->{request} = $self->in_request;
	$self->{headers} = $self->in_headers;

	if ( $self->{request}->[0] =~ /^(?:POST|PUT)/ ) {
		$self->{body} = $self->in_body;
	} else {
		delete $self->{body};
	}
}

sub in_request
{
	my $self = shift;
	local $/ = "\r\n";
	$_ = <STDIN>;
	$self->{head} = $_;
	chomp;
	return [ split /\s+/, $_ ];
}

sub in_headers
{
	my $self = shift;
	local $/ = "\r\n";
	my @headers;
	while ( <STDIN> ) {
		$self->{head} .= $_;
		chomp;
		last unless length $_;
		s/(\S+):\s*//;
		my $header = $1;
		$header =~ tr/-/_/;
		push @headers, ( lc $header, $_ );
	}

	return \@headers;
}

sub in_body
{
	my $self = shift;
	my %headers = @{ $self->{headers} };

	$_ = "";
	my $len = $headers{content_length};
	$len = 10 * 1024 * 1024 unless defined $len;

	read STDIN, $_, $len;
	return $_;
}

sub out_response
{
	my $self = shift;
	my $code = shift;
	print "HTTP/$self->{version} $code\r\n";
}

sub out_headers
{
	my $self = shift;
	while ( my ( $name, $value ) = splice @_, 0, 2 ) {
		$name = join "-", map { ucfirst lc $_ } split /[_-]+/, $name;
		if ( ref $value ) {
			# must be an array
			foreach my $val ( @$value ) {
				print "$name: $val\r\n";
			}
		} else {
			print "$name: $value\r\n";
		}
	}
}

sub out_body
{
	my $self = shift;
	my $body = shift;

	use bytes;
	my $len = length $body;
	print "Content-Length: $len\r\n";
	print "\r\n";
	print $body;
}

sub out_all
{
	my $self = shift;

	my %default_headers = (
		content_type => "text/plain",
		date => $self->_http_time,
	);
	$self->{out_headers} = { %default_headers };

	my $req = $self->{request}->[1];
	$req =~ s#^/##;
	my @args = map { uri_unescape $_ } split m#/#, $req;
	my $func = shift @args;
	$func = "index" unless defined $func and length $func;

	my $body;
	eval {
		$body = $self->$func( @args );
	};
	if ( $@ ) {
		warn "Server error: $@\n";
		$self->out_response( "404 Not Found" );
		$self->out_headers(
			%default_headers
		);
		$self->out_body(
			"Server error: $@\n"
		);
	} elsif ( defined $body ) {
		$self->out_response( $self->{out_code} || "200 OK" );
		$self->out_headers( %{ $self->{out_headers} } );
		$self->out_body( $body );
	}
}

# default handlers
sub index
{
	my $self = shift;
	my $body = "Available functions:\n";
	$body .= ( join "", map "- $_\n", sort { $a cmp $b}
		grep { not __PACKAGE__->can( $_ ) }
		grep { Test::HTTP::Server::Request->can( $_ ) }
		keys %{Test::HTTP::Server::Request::} )
		|| "NONE\n";
	return $body;
}

sub echo
{
	my $self = shift;
	my $type = shift;
	my $body = "";
	if ( not $type or $type eq "head" ) {
		$body .= $self->{head};
	}
	if ( ( not $type or $type eq "body" ) and defined $self->{body} ) {
		$body .= $self->{body};
	}
	return $body;
}

sub cookie
{
	my $self = shift;
	my $num = shift || 1;
	my $template = shift ||
		"test_cookie%n=true; expires=%date(+600); path=/";

	my $expdate = sub {
		my $time = shift;
		$time += time if $time =~ m/^[+-]/;
		return $self->_http_time( $time );
	};
	my @cookies;
	foreach my $n ( 1..$num ) {
		$_ = $template;
		s/%n/$n/;
		s/%date\(\s*([+-]?\d+)\s*\)/$expdate->( $1 )/e;
		push @cookies, $_;
	}
	$self->{out_headers}->{set_cookie} = \@cookies;

	return "Sent $num cookies matching template:\n$template\n";
}

sub repeat
{
	my $self = shift;
	my $num = shift || 1024;
	my $pattern = shift || "=";

	return $pattern x $num;
}

package Test::HTTP::Server::Request;
our @ISA = qw(Test::HTTP::Server::Connection);

1;

__END__

=head1 NAME

Test::HTTP::Server - simple forking http server

=head1 SYNOPSIS

 my $server = Test::HTTP::Server->new();

 client_get( $server->uri . "my_request" );

 sub Test::HTTP::Server::Request::my_request
 {
     my $self = shift;
     return "foobar!\n"
 }

=head1 DESCRIPTION

This package provices a simple forking http server which can be used for
testing http clients.

=head1 DEFAULT METHODS

=over

=item index

Lists user methods.

=item echo / TYPE

Returns whole request in the body. If TYPE is "head", only request head will
be echoed, if TYPE is "body" (i.g. post requests) only body will be sent.

 system "wget", $server->uri . "echo/head";

=item cookie / REPEAT / PATTERN

Sets a cookie. REPEAT is the number of cookies to be sent. PATTERN is the
cookie pattern.

 system "wget", $server->uri . "cookie/3";

=item repeat / REPEAT / PATTERN

Sends a pattern.

 system "wget", $server->uri . "repeat/2/foobar";

=back

=cut
