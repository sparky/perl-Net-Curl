#!perl

use strict;
use warnings;
use Test::More tests => 12;

BEGIN { use_ok( 'WWW::CurlOO::Easy' ); }
use WWW::CurlOO::Easy qw(:constants);

my $url = $ENV{CURL_TEST_URL} || "http://rsget.pl";

my $header_called = 0;
sub header_callback { $header_called++; return length($_[1]) };

my $body_called = 0;
sub body_callback {
	my ($self, $chunk,$handle)=@_;
	$body_called++;
	return length($chunk); # OK
}


# Init the curl session
my $curl1 = WWW::CurlOO::Easy->new();
ok($curl1, 'Curl1 session initialize returns something');
ok(ref($curl1) eq 'WWW::CurlOO::Easy', 'Curl1 session looks like an object from the WWW::CurlOO::Easy module');

my $curl2 = WWW::CurlOO::Easy->new();
ok($curl2, 'Curl2 session initialize returns something');
ok(ref($curl2) eq 'WWW::CurlOO::Easy', 'Curl2 session looks like an object from the WWW::CurlOO::Easy module');

for my $handle ($curl1,$curl2) {
	$handle->setopt(CURLOPT_NOPROGRESS, 1);
	$handle->setopt(CURLOPT_FOLLOWLOCATION, 1);
	$handle->setopt(CURLOPT_TIMEOUT, 30);

	my $body_ref=\&body_callback;
	$handle->setopt(CURLOPT_WRITEFUNCTION, $body_ref);
	$handle->setopt(CURLOPT_HEADERFUNCTION, \&header_callback);
}


ok(! $curl1->setopt(CURLOPT_URL, "zxxypz://whoa"), "Setting deliberately bad protocol succeeds - should return error on perform"); # deliberate error
ok(! $curl2->setopt(CURLOPT_URL, $url), "Setting OK url");

eval { $curl1->perform(); };

ok( $@, "Curl1 handle fails as expected");
ok( $@ == CURLE_UNSUPPORTED_PROTOCOL, "Curl1 handle fails with the correct error");

eval { $curl2->perform(); };
ok( !$@, "Curl2 handle succeeds");

ok($header_called, "Header callback works");
ok($body_called, "Body callback works");
