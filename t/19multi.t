#!perl

use strict;
use warnings;
use Test::More tests => 20;
use WWW::CurlOO::Easy qw(:constants);
use WWW::CurlOO::Multi qw(:constants);
use File::Temp qw/tempfile/;

my $header = tempfile();
my $header2 = tempfile();
my $body = tempfile();
my $body2 = tempfile();

my $url = $ENV{CURL_TEST_URL} || "http://rsget.pl";


sub action_wait {
	my $curlm = shift;
	my ($rin, $win, $ein) = $curlm->fdset;
	my $timeout = $curlm->timeout;
	if ( $timeout > 0 ) {
		my ($nfound,$timeleft) = select($rin, $win, $ein, $timeout);
	}
}

    my $curl = new WWW::CurlOO::Easy;
    $curl->setopt( CURLOPT_URL, $url);
    ok(! $curl->setopt(CURLOPT_WRITEHEADER, $header), "Setting CURLOPT_WRITEHEADER");
    ok(! $curl->setopt(CURLOPT_WRITEDATA,$body), "Setting CURLOPT_WRITEDATA");
    ok( $curl->{private} = "foo" , "Setting private data");

    my $curl2 = new WWW::CurlOO::Easy;
    $curl2->setopt( CURLOPT_URL, $url);
    ok(! $curl2->setopt(CURLOPT_WRITEHEADER, $header2), "Setting CURLOPT_WRITEHEADER");
    ok(! $curl2->setopt(CURLOPT_WRITEDATA,$body2), "Setting CURLOPT_WRITEDATA");
    ok( $curl2->{private} = 42, "Setting private data");

    my $curlm = new WWW::CurlOO::Multi;
    my @fds = $curlm->fdset;
    ok( @fds == 3 && ref($fds[0]) eq '' && ref($fds[1]) eq '' && ref($fds[2]) eq '', "fdset returns 3 vectors");
    ok( ! $fds[0] && ! $fds[1] && !$fds[2], "The three returned vectors are empty");
    $curlm->perform;
    @fds = $curlm->fdset;
    ok( ! $fds[0] && ! $fds[1] && !$fds[2] , "The three returned vectors are still empty after perform");
    $curlm->add_handle($curl);
    @fds = $curlm->fdset;
    ok( ! $fds[0] && ! $fds[1] && !$fds[2] , "The three returned vectors are still empty after perform and add_handle");
    $curlm->perform;
    @fds = $curlm->fdset;
    my $cnt;
    $cnt = unpack( "%b*", $fds[0].$fds[1] );
    ok( $cnt == 1, "The read or write fdset contains one fd (is $cnt)");
    $curlm->add_handle($curl2);
    @fds = $curlm->fdset;
    $cnt = unpack( "%b*", $fds[0].$fds[1] );
    ok( $cnt == 1, "The read or write fdset still only contains one fd (is $cnt)");
    $curlm->perform;
    @fds = $curlm->fdset;
    $cnt = unpack( "%b*", $fds[0].$fds[1] );
    ok( $cnt == 2, "The read or write fdset contains two fds (is $cnt)");
    my $active = 2;
    while ($active != 0) {
	my $ret = $curlm->perform;
	if ($ret != $active) {
		while (my ($curl,$value) = $curlm->info_read) {
			ok( $curl && ( $curl->{private} eq "foo" || $curl->{private}  == 42 ), "The stored private value matches what we set ($curl->{private})");
		}
		$active = $ret;
	}
        action_wait($curlm);
    }
    @fds = $curlm->fdset;
    ok( ! $fds[0] && ! $fds[1] && !$fds[2] , "The three returned arrayrefs are empty after we have no active transfers");
    ok($header, "Header reply exists from first handle");
    ok($body, "Body reply exists from second handle");
    ok($header2, "Header reply exists from second handle");
    ok($body2, "Body reply exists from second handle");
