#!perl

use strict;
use warnings;
use lib 'inc';
use Test::More;
use Test::HTTP::Server;
BEGIN {
	eval 'use Net::Curl::Compat;';
	plan skip_all => $@ if $@;
}
use WWW::Curl::Easy;
use WWW::Curl::Multi;
use File::Temp qw/tempfile/;

my $server = Test::HTTP::Server->new;
plan skip_all => "Could not run http server\n" unless $server;
plan tests => 20;

my $header = tempfile();
my $header2 = tempfile();
my $body = tempfile();
my $body2 = tempfile();

my $url = $server->uri;

sub fhbits {
	my $fhlist = shift;
	my $bits = '';
	for (@{$fhlist}) {
		vec($bits,$_,1) = 1;
	}
	return $bits;
}

sub action_wait {
	my $curlm = shift;
	my ($re, $wr, $err) = $curlm->fdset;
	my ($rin, $win, $ein, $rout, $wout, $eout);
	$rin = $win = $ein = '';
	$rin = fhbits($re);
	$win = fhbits($wr);
	$ein = $rin | $win;
	my ($nfound,$timeleft) = select($rin, $win, $ein, 0.02);
}

    my $curl = new WWW::Curl::Easy;
    $curl->setopt( CURLOPT_URL, $url);
    ok(! $curl->setopt(CURLOPT_WRITEHEADER, $header), "Setting CURLOPT_WRITEHEADER");
    ok(! $curl->setopt(CURLOPT_WRITEDATA,$body), "Setting CURLOPT_WRITEDATA");
    ok(! $curl->setopt(CURLOPT_PRIVATE,"foo"), "Setting CURLOPT_PRIVATE");

    my $curl2 = new WWW::Curl::Easy;
    $curl2->setopt( CURLOPT_URL, $url);
    ok(! $curl2->setopt(CURLOPT_WRITEHEADER, $header2), "Setting CURLOPT_WRITEHEADER");
    ok(! $curl2->setopt(CURLOPT_WRITEDATA,$body2), "Setting CURLOPT_WRITEDATA");
    ok(! $curl2->setopt(CURLOPT_PRIVATE,42), "Setting CURLOPT_PRIVATE");

    my $curlm = new WWW::Curl::Multi;
    my @fds = $curlm->fdset;
    ok( @fds == 3 && ref($fds[0]) && ref($fds[1]) && ref($fds[2]), "fdset returns 3 references");
    ok( ! @{$fds[0]} && ! @{$fds[1]} && !@{$fds[2]} , "The three returned arrayrefs are empty");
    $curlm->perform;
    @fds = $curlm->fdset;
    ok( ! @{$fds[0]} && ! @{$fds[1]} && !@{$fds[2]} , "The three returned arrayrefs are still empty after perform");
    $curlm->add_handle($curl);
    @fds = $curlm->fdset;
    ok( ! @{$fds[0]} && ! @{$fds[1]} && !@{$fds[2]} , "The three returned arrayrefs are still empty after perform and add_handle");
    $curlm->perform;
    @fds = $curlm->fdset;
    ok( 1 || @{$fds[0]} == 1 || @{$fds[1]} == 1, "The read or write fdset contains one fd");
    $curlm->add_handle($curl2);
    @fds = $curlm->fdset;
    ok( 1 || @{$fds[0]} == 1 || @{$fds[1]} == 1, "The read or write fdset still only contains one fd");
    $curlm->perform;
    @fds = $curlm->fdset;
    ok( 2 || @{$fds[0]} + @{$fds[1]} == 2, "The read or write fdset contains two fds");
    my $active = 2;
    while ($active != 0) {
	my $ret = $curlm->perform;
	if ($ret != $active) {
		while (my ($id,$value) = $curlm->info_read) {
			ok($id eq "foo" || $id == 42, "The stored private value matches what we set");
		}
		$active = $ret;
	}
        action_wait($curlm);
    }
    @fds = $curlm->fdset;
    ok( ! @{$fds[0]} && ! @{$fds[1]} && !@{$fds[2]} , "The three returned arrayrefs are empty after we have no active transfers");
    ok($header, "Header reply exists from first handle");
    ok($body, "Body reply exists from second handle");
    ok($header2, "Header reply exists from second handle");
    ok($body2, "Body reply exists from second handle");
