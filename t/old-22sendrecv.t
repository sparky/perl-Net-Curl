#!perl
use strict;
use warnings;
use Test::More;
use WWW::CurlOO::Easy qw(:constants);

my $vi = WWW::CurlOO::version_info();
if ( WWW::CurlOO::LIBCURL_VERSION_NUM() < 0x071202 ) {
	my $ver = WWW::CurlOO::LIBCURL_VERSION();
	plan skip_all => "curl $ver does not support send and recv";
}
plan tests => 7;

# host must support keep-alive connections
my $url = $ENV{CURL_TEST_URL} || "http://rsget.pl";

( my $host = $url ) =~ s#^.*?://##;

# make sure nothing blocks
alarm 5;

my $c = WWW::CurlOO::Easy->new();
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

my $tosend = "GET / HTTP/1.1\r\nHost: $host\r\n\r\n";
my $sent = $c->send( $tosend );

ok( length $tosend == $sent, "sent all data at once" );

$cnt = select $rout = $vec, undef, $eout = $vec, 2;
ok( $cnt, "ready to read" );

my $buffer;

eval {
	$c->recv( $buffer, 1024 * 16 );
};
ok( !$@, "received data" );

alarm 2;
eval {
	1 while $c->recv( $buffer, 1024 * 16 );
};
ok( $@ && ( $@ == CURLE_AGAIN || $@ == CURLE_UNSUPPORTED_PROTOCOL ),
	"no more data to read" );

