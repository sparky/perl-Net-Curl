use strict;
use warnings;
use lib 'inc';
use Test::More;
use Test::HTTP::Server;
use Net::Curl::Easy qw(:constants);

local $ENV{no_proxy} = '*';

my $server = Test::HTTP::Server->new;
plan tests => 4;

my $agent = "ResetTester/1.0";

my $easy = Net::Curl::Easy->new();
$easy->setopt(CURLOPT_USERAGENT, $agent);
$easy->setopt(CURLOPT_URL, $server->uri . "echo/head");

my $body1 = '';
$easy->setopt(CURLOPT_FILE, \$body1);
$easy->perform;

#diag($body1);
like($body1, qr/\b\Q${agent}\E\b/x, "User-Agent set");

$easy->reset;

$easy->setopt(CURLOPT_URL, $server->uri . "echo/head");

my $body2 = '';
$easy->setopt(CURLOPT_FILE, \$body2);
$easy->perform;

#diag($body2);
like($body2, qr{^GET\s+/echo/head\s+HTTP/1\.[01]}x, "was GET");
unlike($body2, qr/\b\Q${agent}\E\b/x, "User-Agent unset");

$easy->reset;

pass("did not die");
