#
# WWW::CurlOO::* objects must not be freed until they have exited correctly,
# problems may appear if someone tried to destroy last reference from a callback.
use strict;
use warnings;
use Test::More tests => 7;
use WWW::CurlOO::Easy qw(:constants);

my $url = $ENV{CURL_TEST_URL} || "http://rsget.pl/";

my $destroyed = 0;
sub DESTROY {
	$destroyed++;
}

my $headercnt = 0;
my $reftype;
my $out = "";

my $curl = WWW::CurlOO::Easy->new();
{ $curl->{guard} = bless \my $foo, __PACKAGE__; }
$curl->setopt( CURLOPT_FILE, \$out );
$curl->setopt( CURLOPT_HEADERFUNCTION, \&cb_header );
$curl->setopt( CURLOPT_URL, $url );
cmp_ok( $destroyed, '==', 0, 'object resources in place' );

$curl->perform();

sub cb_header {
	my ( $easy, $header ) = @_;

	# destroying last reference
	$curl = undef;

	$reftype = ref $easy;
	$headercnt++;
	return length $header;
}

pass( "did not die" );
ok( ! defined $curl, 'curl destroyed' );
cmp_ok( $destroyed, '>', 0, 'object resources freed' );
cmp_ok( $headercnt, '>', 5, "got headers" );
cmp_ok( length $out, '>', 100, "got file" );
is( $reftype, 'WWW::CurlOO::Easy', 'callback received correct object type' );
