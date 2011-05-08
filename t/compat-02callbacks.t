#!perl

use strict;
use warnings;
use lib 'inc';
use Test::More;
use Test::HTTP::Server;
use File::Temp qw/tempfile/;

BEGIN {
	eval 'use Net::Curl::Compat;';
	plan skip_all => $@ if $@;
}
use WWW::Curl::Easy;

my $server = Test::HTTP::Server->new;
plan skip_all => "Could not run http server\n" unless $server;
plan tests => 6;

my $url = $server->uri;

# Init the curl session
my $curl = WWW::Curl::Easy->new();
ok($curl, 'Curl session initialize returns something');
ok(ref($curl) eq 'WWW::Curl::Easy', 'Curl session looks like an object from the WWW::Curl::Easy module');

$curl->setopt(CURLOPT_NOPROGRESS, 1);
$curl->setopt(CURLOPT_FOLLOWLOCATION, 1);
$curl->setopt(CURLOPT_TIMEOUT, 30);

my $head = tempfile();
$curl->setopt(CURLOPT_WRITEHEADER, $head);

my $body = tempfile();
$curl->setopt(CURLOPT_FILE,$body);

$curl->setopt(CURLOPT_URL, $url);

my $header_called = 0;
sub header_callback { $header_called = 1; return length($_[0]) };
my $body_called = 0;
sub body_callback { $body_called++;return length($_[0]) };



ok (! $curl->setopt(CURLOPT_HEADERFUNCTION, \&header_callback), "CURLOPT_HEADERFUNCTION set");
ok (! $curl->setopt(CURLOPT_WRITEFUNCTION, \&body_callback), "CURLOPT_WRITEFUNCTION set");

$curl->perform();
ok($header_called, "CURLOPT_HEADERFUNCTION callback was used");
ok($body_called, "CURLOPT_WRITEFUNCTION callback was used");
