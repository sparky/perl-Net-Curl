#!perl
use strict;
use warnings;
use lib 'inc';
use Test::More;
use Test::HTTP::Server;
use Net::Curl::Easy qw(:constants);

my $vi = Net::Curl::version_info();
if ( Net::Curl::LIBCURL_VERSION_NUM() < 0x071202 ) {
	my $ver = Net::Curl::LIBCURL_VERSION();
	plan skip_all => "curl $ver does not support send and recv";
}

my $server = Test::HTTP::Server->new;
plan skip_all => "Could not run http server\n" unless $server;
plan tests => 7;

# host must support keep-alive connections
my $url = $server->uri;

( my $host = $url ) =~ s#^.*?://##;

# make sure nothing blocks
alarm 5;

my $c = Net::Curl::Easy->new();
$c->setopt( CURLOPT_URL, $url );
$c->setopt( CURLOPT_CONNECT_ONLY, 1 );

eval { $c->perform(); };
ok( !$@, "perform didn't block" );

my $socket = $c->getinfo( CURLINFO_LASTSOCKET );
ok( $socket > 2, "open socket" );

my $vec = '';
vec( $vec, $socket, 1 ) = 1;
my ($rout, $wout, $eout);

my $cnt;
$cnt = select undef, $wout = $vec, $eout = $vec, 1;
ok( $cnt, "ready to write" );

my $tosend = "GET /repeat/10/qwertyuiop HTTP/1.1\r\nHost: $host\r\n\r\n";
my $sent = $c->send( $tosend );

ok( length $tosend == $sent, "sent all data at once" );

$cnt = select $rout = $vec, undef, $eout = $vec, 2;
ok( $cnt, "ready to read" );

my $buffer;
eval {
	for (;;) {
		# check if the socket is readable
		1 until select $rout = $vec, undef, $eout = $vec, 2;
		$c->recv( $buffer, 1024 );
		# check if the whole pattern was received
		last if $buffer =~ /(?:qwertyuiop){10}/;
	}
};
ok( !$@, "received data" );

alarm 2;
my $received = 0;
eval {
	for (;;) {
		my $n = $c->recv( $buffer, 1024 );
		last unless $n;
		$received += $n;
	}
};
ok( ( !$@ && !$received ) || ( $@ == CURLE_AGAIN() || $@ == CURLE_UNSUPPORTED_PROTOCOL() ),
	"no more data to read" );

