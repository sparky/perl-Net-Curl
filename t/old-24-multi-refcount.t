#!perl

use strict;
use warnings;
use lib 'inc';
use Test::More;
use Test::HTTP::Server;
use Net::Curl::Easy qw(:constants);
use Net::Curl::Multi qw(:constants);
use Scalar::Util qw(weaken);

my $server = Test::HTTP::Server->new;
plan skip_all => "Could not run http server\n" unless $server;
plan tests => 5;

my $url = $server->uri;

sub action_wait {
	my $curlm = shift;
	my ($rin, $win, $ein) = $curlm->fdset;
	my $timeout = $curlm->timeout;
	if ( $timeout > 0 ) {
		my ($nfound,$timeleft) = select($rin, $win, $ein, $timeout / 1000);
	}
}

sub cb_write
{
	die "lost private data"
		unless $_[0]->{private} eq "foo";

	return length $_[1];
}

my $ref;

my $curlm = new Net::Curl::Multi;
{
	my $curl = Net::Curl::Easy->new();
	$curl->setopt( CURLOPT_URL, $url );
	$curl->setopt( CURLOPT_HEADERFUNCTION, \&cb_write );
	$curl->setopt( CURLOPT_WRITEHEADER, "head");
	$curl->setopt( CURLOPT_WRITEFUNCTION, \&cb_write );
	$curl->setopt( CURLOPT_FILE, "body");
	$curl->{private} = "foo";
	$curlm->add_handle( $curl );

	$ref = \$curl->{private};
	weaken( $ref );

	# here $easy goes out of scope
	# but multi should keep it alive
}

ok( $ref, "Ref alive" );
ok( $$ref eq "foo", "Ref correct" );

do {
        action_wait( $curlm );
} while ( $curlm->perform );

ok( $ref, "Ref alive $$ref" );
ok( $$ref eq "foo", "Ref correct" );

{
	my ( $msg, $easy, $value ) = $curlm->info_read;

	$curlm->remove_handle( $easy );

	# here $easy goes out of scope
	# and it should die
}

ok( !defined ( $ref ), "ref no longer reachable" );
