#
# This may crash if we also destroy the last ref.
use strict;
use warnings;
use Test::More tests => 6;
use WWW::CurlOO::Easy qw(:constants);

my $url = $ENV{CURL_TEST_URL} || "http://rsget.pl/";

my $destroyed = 0;
sub DESTROY {
	$destroyed++;
}

my $headercnt = 0;
my $reftype;
my $out = "";

my $base = {};
my $curl = WWW::CurlOO::Easy->new( $base );

is( ref $curl, 'WWW::CurlOO::Easy', 'correct object' );
is( ref $base, 'WWW::CurlOO::Easy', 'correct object' );

# alter base
$base = "foo";

is( ref $curl, 'WWW::CurlOO::Easy', 'correct object' );
is( ref $base, '', 'base has no object' );

{ $curl->{guard} = bless \my $foo, __PACKAGE__; }
$curl->setopt( CURLOPT_FILE, \$out );
$curl->setopt( CURLOPT_HEADERFUNCTION, \&cb_header );
$curl->setopt( CURLOPT_URL, $url );

$curl->perform();

sub cb_header {
	my ( $easy, $header ) = @_;

	$reftype = ref $easy;
	$headercnt++;
	return length $header;
}

pass( "did not die" );
is( $reftype, 'WWW::CurlOO::Easy', 'callback received correct object type' );
