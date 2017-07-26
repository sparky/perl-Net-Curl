#!/usr/bin/perl
use strict;
use warnings qw(all);
use lib 'inc';

use Test::More;
use Test::HTTP::Server;

use Net::Curl::Easy qw(/^CURL_WAIT_/);
use Net::Curl::Multi;


plan skip_all => "curl_multi_wait() is implemented since libcurl/7.28.0"
    if Net::Curl::LIBCURL_VERSION_NUM() < 0x071C00;

my $multi = Net::Curl::Multi->new()
	or die "I forgot how to curl\n";

pipe my $fh_read, my $fh_write;

my $ev_write = {
	fd => fileno $fh_write,
	events => CURL_WAIT_POLLOUT(),
};
my $ev_read = {
	fd => fileno $fh_read,
	events => CURL_WAIT_POLLIN(),
};

alarm 2;

my $ret = $multi->wait( [ $ev_read ], 100 );

is( $ret, 0, "Expect nothing" );

ok( (not $ev_read->{revents}), "No events here" );

$ret = $multi->wait( [ $ev_read, $ev_write ], 500 );

is( $ret, 1, "One handle ready" );

ok( (not $ev_read->{revents}), "No events to read" );
is( $ev_write->{revents}, CURL_WAIT_POLLOUT(), "Ready to write" );

print $fh_write "Hello!\n";
$fh_write->flush();

$ret = $multi->wait( [ $ev_read ], 500 );
is( $ret, 1, "One handle ready" );
is( $ev_read->{revents}, CURL_WAIT_POLLIN(), "Ready to read" );

$ev_read->{revents} = 0;
$ret = $multi->wait( [ $ev_read ], 500 );
is( $ret, 1, "One handle ready" );
is( $ev_read->{revents}, CURL_WAIT_POLLIN(), "Ready to read" );

my $line = <$fh_read>;

$ret = $multi->wait( [ $ev_read ], 100 );
is( $ret, 0, "Nothing ready" );
is( $ev_read->{revents}, CURL_WAIT_POLLIN(), "Ready to read, because we did not reset" );

$ev_read->{revents} = 0;
$ret = $multi->wait( [ $ev_read ], 100 );
is( $ret, 0, "Nothing ready" );
ok( !$ev_read->{revents}, "No events here" );

done_testing(13);
