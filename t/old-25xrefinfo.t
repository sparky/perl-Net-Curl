#!perl

use strict;
use warnings;
use lib 'inc';
use Test::More;
use Test::HTTP::Server;
use File::Temp qw/tempfile/;
use Net::Curl::Easy qw(:constants);

BEGIN {
plan skip_all => "CURLOPT_XFERINFOFUNCTION is not available untill version 7.32.0"
    if Net::Curl::LIBCURL_VERSION_NUM() < 0x072000;
}
my $server = Test::HTTP::Server->new;
plan skip_all => "Could not run http server\n" unless $server;
plan tests => 17;

# Init the curl session
my $curl = Net::Curl::Easy->new();
ok($curl, 'Curl session initialize returns something');
ok(ref($curl) eq 'Net::Curl::Easy', 'Curl session looks like an object from the Net::Curl::Easy module');

ok(! $curl->setopt(CURLOPT_NOPROGRESS, 0), "Setting CURLOPT_NOPROGRESS");
ok(! $curl->setopt(CURLOPT_FOLLOWLOCATION, 1), "Setting CURLOPT_FOLLOWLOCATION");
ok(! $curl->setopt(CURLOPT_TIMEOUT, 30), "Setting CURLOPT_TIMEOUT");

my $head = tempfile();
ok(! $curl->setopt(CURLOPT_WRITEHEADER, $head), "Setting CURLOPT_WRITEHEADER");

my $body = tempfile();
ok(! $curl->setopt(CURLOPT_FILE,$body), "Setting CURLOPT_FILE");

ok(! $curl->setopt(CURLOPT_URL, $server->uri), "Setting CURLOPT_URL");

my @myheaders;
$myheaders[0] = "Server: www";
$myheaders[1] = "User-Agent: Perl interface for libcURL";
ok(! $curl->setopt(CURLOPT_HTTPHEADER, \@myheaders), "Setting CURLOPT_HTTPHEADER");

ok(! $curl->setopt(CURLOPT_XFERINFODATA, "xferinfo data"), "Setting CURLOPT_XFERINFODATA");

my $xferinfo_called = 0;
my $xferinfo_data = '';
my $last_dlnow = 0;
sub prog_callb
{
    my ($clientp, $dltotal, $dlnow, $ultotal, $ulnow, $data)=@_;
    $last_dlnow=$dlnow;
    $xferinfo_called++;
    $xferinfo_data = $data;
    return 0;
}                        

ok (! $curl->setopt(CURLOPT_XFERINFOFUNCTION, \&prog_callb), "Setting CURLOPT_XFERINFOFUNCTION");

ok (! $curl->setopt(CURLOPT_XFERINFODATA, "test-data"), "Setting CURLOPT_XFERINFODATA");

ok (! $curl->setopt(CURLOPT_NOPROGRESS, 0), "Turning xferinfo meter back on");

eval { $curl->perform() };
ok (!$@, "Performing perform");

ok ($xferinfo_called, "Progress callback called");

ok ($xferinfo_data eq "test-data", "CURLOPT_XFERINFODATA is used correctly");

ok ($last_dlnow, "Last downloaded chunk non-zero");
