#!perl

use strict;
use warnings;
use lib 'inc';
use Test::More;
use Test::HTTP::Server;
use File::Temp qw/tempfile/;
use Net::Curl::Easy qw(:constants);

my $server = Test::HTTP::Server->new;
plan skip_all => "Could not run http server\n" unless $server;
plan tests => 7;

# Init the curl session
my $curl = Net::Curl::Easy->new();
ok($curl, 'Curl session initialize returns something');
ok(ref($curl) eq 'Net::Curl::Easy', 'Curl session looks like an object from the Net::Curl::Easy module');

$curl->setopt(CURLOPT_NOPROGRESS, 1);
$curl->setopt(CURLOPT_FOLLOWLOCATION, 1);
$curl->setopt(CURLOPT_TIMEOUT, 30);

my $head = tempfile();
ok(! $curl->setopt(CURLOPT_WRITEHEADER, $head), "Setting CURLOPT_WRITEHEADER");

my $body = tempfile();
ok(! $curl->setopt(CURLOPT_FILE,$body), "Setting CURLOPT_FILE");

ok(! $curl->setopt(CURLOPT_URL, $server->uri), "Setting CURLOPT_URL");

my $body_abort_called = 0;
sub body_abort_callback { $body_abort_called++; return -1 };

$curl->setopt(CURLOPT_WRITEFUNCTION, \&body_abort_callback);

eval { $curl->perform(); };
ok( $@, "Request fails, Abort succeeds");

ok( $body_abort_called, "Abort function was invoked");
