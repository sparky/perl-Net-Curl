#
# When destorying an object it may trigger some more callbacks, this may revive
# the object and lead to a subsequent crash.
#
use strict;
use warnings;
use Test::More tests => 9;
use WWW::CurlOO::Easy qw(:constants);

my $ftp_uri = 'ftp://ftp.cpan.org/pub/CPAN/README';

my $headercnt = 0;
my $reftype;
sub cb_header {
	my ( $easy, $header ) = @_;
	$reftype = ref $easy;
	$headercnt++;
	return length $header;
}

my $destroyed = 0;
sub DESTROY {
	$destroyed++;
}

my $out = "";

my $curl = WWW::CurlOO::Easy->new();
{ $curl->{guard} = bless \my $foo, __PACKAGE__; }
$curl->setopt( CURLOPT_FILE, \$out );
$curl->setopt( CURLOPT_HEADERFUNCTION, \&cb_header );
$curl->setopt( CURLOPT_URL, $ftp_uri );
cmp_ok( $destroyed, '==', 0, 'object resources in place' );
$curl->perform();

cmp_ok( $destroyed, '==', 0, 'object resources in place' );
cmp_ok( $headercnt, '>', 5, "got headers" );
cmp_ok( length $out, '>', 1000, "got file" );
is( $reftype, 'WWW::CurlOO::Easy', 'callback received correct object type' );

$headercnt = 0;
$reftype = "";

# force disconnect
#
# this will trigger some more header callbacks, which may crash the
# interpreter
$curl = undef;

pass( "did not die" );
cmp_ok( $headercnt, '>', 0, "received more headers" );
is( $reftype, 'WWW::CurlOO::Easy', 'callback received correct object type' );
cmp_ok( $destroyed, '>', 0, 'object resources freed' );
