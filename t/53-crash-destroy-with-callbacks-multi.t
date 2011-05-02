#
# When destorying an object it may trigger some more callbacks, this may revive
# the object and lead to a subsequent crash.
#
use strict;
use warnings;
use Test::More tests => 9;
use Net::Curl::Easy qw(:constants);

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

my $curl = Net::Curl::Easy->new();
my $multi = Net::Curl::Multi->new();
{ $curl->{guard} = bless \my $foo, __PACKAGE__; }
{ $multi->{guard} = bless \my $bar, __PACKAGE__; }
$curl->setopt( CURLOPT_FILE, \$out );
$curl->setopt( CURLOPT_HEADERFUNCTION, \&cb_header );
$curl->setopt( CURLOPT_URL, $ftp_uri );
cmp_ok( $destroyed, '==', 0, 'object resources in place' );

$multi->add_handle( $curl );
$curl = undef;

cmp_ok( $destroyed, '==', 0, 'object resources in place' );

while ( $multi->handles ) {
	my $t = $multi->timeout;
	if ( $t != 0 ) {
		$t = 10000 if $t < 0;
		my ( $r, $w, $e ) = $multi->fdset;

		select $r, $w, $e, $t / 1000;
	}

	my $ret = $multi->perform();
	if ( ! $ret ) {
		while ( my ( $msg, $easy, $result ) = $multi->info_read() ) {
			$multi->remove_handle( $easy );
		}
	}
};

cmp_ok( $destroyed, '>', 0, 'object resources freed' );
cmp_ok( $headercnt, '>', 5, "got headers" );
cmp_ok( length $out, '>', 1000, "got file" );
is( $reftype, 'Net::Curl::Easy', 'callback received correct object type' );

$destroyed = 0;
$headercnt = 0;
$reftype = "";

# force disconnect
#
# this will trigger some more header callbacks, which may crash the
# interpreter
$multi = undef;

pass( "did not die" );
cmp_ok( $headercnt, '==', 0, "not received more headers" );
cmp_ok( $destroyed, '>', 0, 'object resources freed' );
