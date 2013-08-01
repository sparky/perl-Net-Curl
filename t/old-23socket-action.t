#!perl

use strict;
use warnings;
use lib 'inc';
use Test::More;
use Test::HTTP::Server;
use Net::Curl::Easy qw(:constants);
use Net::Curl::Multi qw(:constants);

local $ENV{no_proxy} = '*';

BEGIN {
	plan skip_all => "libcurl 7.16.0+ is required"
		if Net::Curl::LIBCURL_VERSION_NUM < 0x071000;
}

my $server = Test::HTTP::Server->new;
plan skip_all => "Could not run http server\n" unless $server;
plan tests => 14;

my ($head1, $head2, $body1, $body2 );
open my $_head1, ">", \$head1;
open my $_body1, ">", \$body1;
open my $_head2, ">", \$head2;
open my $_body2, ">", \$body2;

my $url = $server->uri . "slow";
sub Test::HTTP::Server::Request::slow
{
	my $self = shift;

	select undef, undef, undef, 0.5;
	STDOUT->autoflush( 1 );
	$self->out_response( "200 OK" );
	select undef, undef, undef, 0.5;
	$self->out_headers( %{ $self->{out_headers} } );
	select undef, undef, undef, 0.5;
	$self->out_body( "We're good !" x 1000 );
	select undef, undef, undef, 0.5;
	return undef;
}

my $sock_read = 0;
my $sock_write = 0;
my $sock_read_all = 0;
my $sock_write_all = 0;
my $sock_change = 0;

my $vec_read = '';
my $vec_write = '';

my ($vec_r, $vec_w, $vec_e);

my $timer_change = 0;
my $timeout = undef;

sub on_socket
{
	my ( $multi, $easy, $socket, $what, $socketdata_now_undef, $userdata ) = @_;
	#warn "on_socket( $socket, $what )\n";

	$sock_change++;
	if ( $what == CURL_POLL_NONE ) {
		#warn "on_socket: register, not interested in readiness\n";
		vec( $vec_read, $socket, 1 ) = 0;
		vec( $vec_write, $socket, 1 ) = 0;
	} elsif ( $what == CURL_POLL_IN ) {
		#warn "on_socket: register, interested in read readiness\n";
		$sock_read++;
		$sock_read_all++;
		vec( $vec_read, $socket, 1 ) = 1;
		vec( $vec_write, $socket, 1 ) = 0;
	} elsif ( $what == CURL_POLL_OUT ) {
		#warn "on_socket: register, interested in write readiness\n";
		$sock_write++;
		$sock_write_all++;
		vec( $vec_read, $socket, 1 ) = 0;
		vec( $vec_write, $socket, 1 ) = 1;
	} elsif ( $what == CURL_POLL_INOUT ) {
		#warn "on_socket: register, interested in both read and write readiness\n";
		$sock_read++;
		$sock_read_all++;
		$sock_write++;
		$sock_write_all++;
		vec( $vec_read, $socket, 1 ) = 1;
		vec( $vec_write, $socket, 1 ) = 1;
	} elsif ( $what == CURL_POLL_REMOVE ) {
		#warn "on_socket: unregister\n";
		$sock_read--;
		$sock_write--;
		vec( $vec_read, $socket, 1 ) = 0;
		vec( $vec_write, $socket, 1 ) = 0;
	} else {
		die "on_socket: unknown action code\n";
	}
}

sub on_timer
{
	my ( $multi, $timeout_ms, $userdata ) = @_;
	#warn "on_timer( $timeout_ms )\n";
	$timer_change++;
	if ( $timeout_ms < 0 ) {
		$timeout = 1.0;
	} else {
		$timeout = $timeout_ms / 1000;
	}
}

my $curl1 = Net::Curl::Easy->new();
$curl1->setopt( CURLOPT_URL, $url );
$curl1->setopt( CURLOPT_WRITEHEADER, $_head1 );
$curl1->setopt( CURLOPT_WRITEDATA, $_body1 );
$curl1->{name} = "one";

my $curl2 = Net::Curl::Easy->new();
$curl2->setopt( CURLOPT_URL, $url );
$curl2->setopt( CURLOPT_WRITEHEADER, $_head2 );
$curl2->setopt( CURLOPT_WRITEDATA, $_body2 );
$curl2->{name} = "two";

my $curlm = Net::Curl::Multi->new();
$curlm->setopt( CURLMOPT_SOCKETFUNCTION, \&on_socket );
$curlm->setopt( CURLMOPT_TIMERFUNCTION, \&on_timer );
$curlm->add_handle( $curl1 );
$curlm->add_handle( $curl2 );

# init
my $active = $curlm->socket_action();
ok( defined $timeout, "timeout set" );

#warn "main loop\n";
do {
	my $active_now;
	my ($cnt, $timeleft) = select $vec_r = $vec_read, $vec_w = $vec_write,
		$vec_e = $vec_read | $vec_write, $timeout;
	$timeout = $timeleft;
	if ( $cnt ) {
		my $maxfd = 8 * length( $vec_e ) - 1;
		foreach my $i ( 0..$maxfd ) {
			my $bitmask = 0;
			$bitmask |= CURL_CSELECT_IN
				if vec $vec_r, $i, 1;
			$bitmask |= CURL_CSELECT_OUT
				if vec $vec_w, $i, 1;
			$bitmask |= CURL_CSELECT_ERR
				if vec $vec_e, $i, 1;

			next unless $bitmask;

			#warn "socket_action( $i, $bitmask );\n";
			$active_now = $curlm->socket_action( $i, $bitmask );
		}
	} else {
		#warn "socket_action( CURL_SOCKET_TIMEOUT, 0 );\n";
		$active_now = $curlm->socket_action( CURL_SOCKET_TIMEOUT, 0 );
	}

	if ( $active_now != $active ) {
		while (my ($msg, $easy, $value) = $curlm->info_read) {
			$curlm->remove_handle( $easy );
			#warn "Reaped child: $id, $value\n";
			ok( $value == 0, "child $easy->{name} exited correctly" );
		}
		$active = $active_now;
	}
} while ( $active );

#warn "done\n";
ok( $timer_change > 0, "timeout updated" );
ok( $sock_read_all == 2, "registered 2 sockets for reading3 (is $sock_read_all -- $sock_change)" );
ok( $sock_change > 0, "on_socket called ($sock_change)" );
# may be 0 if server responds inmediatelly
#ok( $sock_write_all == 2, "registered 2 sockets for writing (is $sock_write_all)" );
ok( $sock_read <= 0, "deregistered all sockets for reading" );
ok( $sock_write <= 0, "deregistered all sockets for writing" );

$timer_change = 0;
$sock_change = 0;

$curlm->socket_action( CURL_SOCKET_TIMEOUT, 0 );
ok( $timer_change == 0, "nothing unexpected happened: timer" );
ok( $sock_change == 0, "nothing unexpected happened: socket" );

ok( length $head1, "received head1" );
ok( length $head2, "received head2" );
ok( 12000 == length $body1, "received body1" );
ok( 12000 == length $body2, "received body2" );
