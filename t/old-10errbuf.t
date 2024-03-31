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

ok(! $curl->setopt(CURLOPT_URL, "http://0.0.0.0:123456"), "Setting CURLOPT_URL succeeds, even with a bad port");

eval { $curl->perform(); };
ok( $@, "Non-zero return code indicates the expected failure");

seek $new_error, 0, 0;
my $line = <$new_error>;
chomp $line;
if ($line eq "* processing: http://0.0.0.0:123456") {
    $line = <$new_error>;
    chomp $line;
}
like( $line, qr(^\*\s+(?:
    Closing \s connection \s -1 |
    URL \s using \s bad/illegal \s format \s or \s missing URL |
    URL \s rejected: \s Port \s number \s was \s not \s a \s decimal \s number \s between \s 0 \s and \s 65535 |
    Port \s number \s too \s large: \s 123456 |
    Rebuilt \s URL \s to: \s http://0.0.0.0:123456/
)$)ix, "Reading redirected STDERR" );

unlink $tempname;
