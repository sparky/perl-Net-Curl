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
plan tests => 13;

# Init the curl session
my $curl = Net::Curl::Easy->new();
ok($curl, 'Curl session initialize returns something');
ok(ref($curl) eq 'Net::Curl::Easy', 'Curl session looks like an object from the Net::Curl::Easy module');

ok(! $curl->setopt(CURLOPT_VERBOSE, 1), "Setting CURLOPT_VERBOSE");
ok(! $curl->setopt(CURLOPT_NOPROGRESS, 1), "Setting CURLOPT_NOPROGRESS");
ok(! $curl->setopt(CURLOPT_FOLLOWLOCATION, 1), "Setting CURLOPT_FOLLOWLOCATION");
ok(! $curl->setopt(CURLOPT_TIMEOUT, 30), "Setting CURLOPT_TIMEOUT");

my $head = tempfile();
ok(! $curl->setopt(CURLOPT_WRITEHEADER, $head), "Setting CURLOPT_WRITEHEADER");

my $body = tempfile();
ok(! $curl->setopt(CURLOPT_FILE, $body), "Setting CURLOPT_FILE");

ok(! $curl->setopt(CURLOPT_URL, $server->uri), "Setting CURLOPT_URL");

my ( $new_error, $tempname ) = tempfile();
ok(! $curl->setopt(CURLOPT_STDERR, $new_error), "Setting CURLOPT_STDERR");

# create a (hopefully) bad URL, so we get an error

ok(! $curl->setopt(CURLOPT_URL, "badprotocol://127.0.0.1:2"), "Setting CURLOPT_URL succeeds, even with a bad protocol");

eval { $curl->perform(); };
ok( $@, "Non-zero return code indicates the expected failure");

seek $new_error, 0, 0;
my $line = <$new_error>;
like( $line, qr/^\*\s+(?:
    Protocol \s badprotocol \s not \s supported \s or \s disabled \s in \s libcurl |
    Unsupported \s protocol: \s badprotocol |
    Rebuilt \s URL \s to: \s badprotocol:\/\/.+
)$/x, "Reading redirected STDERR" );

unlink $tempname;
