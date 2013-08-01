#
# Stupid bug in getinfo
use strict;
use warnings;
use lib 'inc';
use Test::More;
use Test::HTTP::Server;
use Net::Curl::Easy qw(:constants);

local $ENV{no_proxy} = '*';

my $server = Test::HTTP::Server->new;
plan skip_all => "Could not run http server\n" unless $server;
plan tests => 4;

my $easy = Net::Curl::Easy->new();
$easy->setopt( CURLOPT_URL, $server->uri . "cookie" );
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
