#
# Stupid bug in getinfo
use strict;
use warnings;
use Test::More tests => 4;
use Net::Curl::Easy qw(:constants);

# must be some uri that sets cookies
my $url = $ENV{CURL_TEST_URL} || "http://www.google.com/";

my $easy = Net::Curl::Easy->new();
$easy->setopt( CURLOPT_URL, $url );
$easy->setopt( CURLOPT_FOLLOWLOCATION, 1 );
$easy->setopt( CURLOPT_COOKIEFILE, '' );
$easy->setopt( CURLOPT_WRITEDATA, \my $body );

my $slist = $easy->getinfo( CURLINFO_COOKIELIST );

pass( "did not die" );
ok( ! defined $slist, 'slist is undef' );

$easy->perform();

$slist = $easy->getinfo( CURLINFO_COOKIELIST );

pass( "did not die" );
is( ref $slist, 'ARRAY', 'slist is an array' );

$" = "\n- ";
#diag( "- @$slist\n" );
