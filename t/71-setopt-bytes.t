#!perl
#
# setopt() must pass bytes, not Perl's internal representation (#60).
use strict;
use warnings;
use lib 'inc';
use Test::More;
use Test::HTTP::Server;
use Net::Curl::Easy qw(:constants);

my $server = Test::HTTP::Server->new;
plan skip_all => "Could not run http server\n" unless $server;
plan tests => 6;

sub post {
	my ( $payload, $header ) = @_;
	my $easy = Net::Curl::Easy->new;
	my $out = "";
	$easy->setopt( CURLOPT_URL, $server->uri . "echo" );
	$easy->setopt( CURLOPT_COPYPOSTFIELDS, $payload );
	$easy->setopt( CURLOPT_HTTPHEADER, [ $header ] ) if defined $header;
	$easy->setopt( CURLOPT_WRITEDATA, \$out );
	$easy->perform;
	return $out;
}

my $bytes = "\xe9p\xe9e";
my $upgraded = $bytes;
utf8::upgrade( $upgraded );

my $out = post( $bytes );
like( $out, qr/^Content-Length: 4\r?$/m, 'downgraded string sent as 4 bytes' );

$out = post( $upgraded );
like( $out, qr/^Content-Length: 4\r?$/m, 'upgraded string sent as the same 4 bytes' );
ok( index( $out, "\r\n\r\n$bytes" ) >= 0, 'body bytes match' );

$out = post( "x", "X-Test: $upgraded" );
like( $out, qr/^X-Test: \Q$bytes\E\r?$/m, 'upgraded slist entry sent as bytes' );

ok( ! eval { post( "\x{263a}" ); 1 }, 'wide character in string dies' );
like( $@, qr/Wide character/, '... with Wide character error' );
