#
# try to connect to an arbitrary host and change connection destination
# on-the-fly
#
use strict;
use warnings;
use lib 'inc';
use Test::More;
use Test::HTTP::Server;
use Socket qw(:all);
use Net::Curl::Easy qw(:constants);

local $ENV{no_proxy} = '*';

BEGIN {
	plan skip_all => "libcurl 7.17.1+ is required"
		if Net::Curl::LIBCURL_VERSION_NUM < 0x071101;
}

my $server = Test::HTTP::Server->new;
plan skip_all => "Could not run http server\n" unless $server;
plan tests => 7;

my $out = "";

my $curl = Net::Curl::Easy->new();
$curl->setopt( CURLOPT_FILE, \$out );
$curl->setopt( CURLOPT_OPENSOCKETFUNCTION, \&cb_opensocket );
$curl->setopt( CURLOPT_URL, "http://1.1.1.1:666/" );

$curl->perform();

sub cb_opensocket {
	my ( $easy, $purpose, $addr ) = @_;

	my ( $port, $ip ) = unpack_sockaddr_in( $addr->{addr} );
	my $ips = inet_ntoa( $ip );

	is( $purpose, CURLSOCKTYPE_IPCXN, 'purpose is CURLSOCKTYPE_IPCXN' );
	is( $ips, "1.1.1.1", "IP is correct" );
	is( $port, "666", "Port is correct" );
	is( $addr->{family}, AF_INET, "family is AF_INET" );
	is( $addr->{socktype}, SOCK_STREAM, "socktype is SOCK_STREAM" );
	ok( $addr->{protocol} == IPPROTO_IP ||
		$addr->{protocol} == IPPROTO_TCP,
		"protocol is IPPROTO_IP or IPPROTO_TCP ($addr->{protocol})" );

	socket my $s, $addr->{family}, $addr->{socktype}, $addr->{protocol};

	my $f = fileno $s;

	# must save a reference somewhere, otherwise perl will close it
	$easy->{ "fd$f" } = $s;

	$addr->{addr} = pack_sockaddr_in( $server->port,
		inet_aton( $server->address ) );
	
	return $f;
}

cmp_ok( length $out, '==', 26, "got file" );
