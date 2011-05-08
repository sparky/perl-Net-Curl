#
# This may crash if we also destroy the last ref.
use strict;
use warnings;
use lib 'inc';
use Test::More;
use Test::HTTP::Server;
use Net::Curl::Easy qw(:constants);

my $server = Test::HTTP::Server->new;
plan skip_all => "Could not run http server\n" unless $server;
plan tests => 6;

my $destroyed = 0;
sub DESTROY {
	$destroyed++;
}

my $headercnt = 0;
my $reftype;
my $out = "";

my $base = {};
my $curl = Net::Curl::Easy->new( $base );

is( ref $curl, 'Net::Curl::Easy', 'correct object' );
is( ref $base, 'Net::Curl::Easy', 'correct object' );

# alter base
$base = "foo";

is( ref $curl, 'Net::Curl::Easy', 'correct object' );
is( ref $base, '', 'base has no object' );

{ $curl->{guard} = bless \my $foo, __PACKAGE__; }
$curl->setopt( CURLOPT_FILE, \$out );
$curl->setopt( CURLOPT_HEADERFUNCTION, \&cb_header );
$curl->setopt( CURLOPT_URL, $server->uri );

$curl->perform();

sub cb_header {
	my ( $easy, $header ) = @_;

	$reftype = ref $easy;
	$headercnt++;
	return length $header;
}

pass( "did not die" );
is( $reftype, 'Net::Curl::Easy', 'callback received correct object type' );
