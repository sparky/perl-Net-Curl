#
# When destorying an object it may trigger some more callbacks, this may revive
# the object and lead to a subsequent crash.
#
use strict;
use warnings;
use Config;
use Test::More;
use Net::Curl::Easy qw(:constants);

plan skip_all => "This test requires reliable Internet connection. "
	. "Set AUTOMATED_TESTING env variable to run this test."
	unless $ENV{AUTOMATED_TESTING};
plan skip_all => "FreeBSD stock libcurl might have broken proxy support. "
    if $Config{osname} eq 'freebsd';
plan tests => 8;

# my $ftp_uri = 'ftp://ftp.cpan.org/pub/CPAN/README';
my $ftp_uri = 'http://www.cpan.org/README';

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

my $curl = Net::Curl::Easy->new();
{ $curl->{guard} = bless {}, __PACKAGE__; }
$curl->setopt( CURLOPT_FILE, \$out );
$curl->setopt( CURLOPT_HEADERFUNCTION, \&cb_header );
$curl->setopt( CURLOPT_URL, $ftp_uri );
cmp_ok( $destroyed, '==', 0, 'object resources in place' );
$curl->perform();

cmp_ok( $destroyed, '==', 0, 'object resources in place' );
cmp_ok( $headercnt, '>', 5, "got headers" );
cmp_ok( length $out, '>', 1000, "got file" );
is( $reftype, 'Net::Curl::Easy', 'callback received correct object type' );

$headercnt = 0;
$reftype = "";

# force disconnect
#
# this will trigger some more header callbacks, which may crash the
# interpreter
$curl = undef;

pass( "did not die" );
cmp_ok( $headercnt, '==', 0, "not received more headers" );
cmp_ok( $destroyed, '>', 0, 'object resources freed' );
