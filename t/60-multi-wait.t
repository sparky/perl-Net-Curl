#!/usr/bin/perl
use strict;
use warnings qw(all);
use lib 'inc';

use Test::More;
use Test::HTTP::Server;

use Net::Curl::Easy qw(:constants);
use Net::Curl::Multi qw(:constants);

local $ENV{no_proxy} = '*';

plan skip_all => "curl_multi_wait() is implemented since libcurl/7.28.0"
    if Net::Curl::LIBCURL_VERSION_NUM() < 0x071C00;

my $server = Test::HTTP::Server->new;
my $multi = Net::Curl::Multi->new;
my $n = 5;

for my $i (1 .. $n) {
    my $easy = Net::Curl::Easy->new() or die "cannot curl";
    $multi->add_handle($easy);

    $easy->setopt(CURLOPT_NOPROGRESS, 1);
    $easy->setopt(CURLOPT_FOLLOWLOCATION, 1);
    $easy->setopt(CURLOPT_TIMEOUT, 30);

    open(my $head, "+>", undef);
    Net::Curl::Easy::setopt($easy, CURLOPT_WRITEHEADER, $head);
    open(my $body, "+>", undef);
    Net::Curl::Easy::setopt($easy, CURLOPT_WRITEDATA, $body);

    $easy->setopt(CURLOPT_URL, $server->uri . "repeat/$i/abc");
}

my $running = 0;
do {
    $multi->wait(1000);
    $running = $multi->perform;
    while (my (undef, $easy, $result) = $multi->info_read) {
        is(0 + $result, CURLE_OK, 'curl returns OK');
        like($easy->getinfo(CURLINFO_EFFECTIVE_URL), qr{/repeat/\d+/abc$}x, 'URL matches');
        is(200, $easy->getinfo(CURLINFO_HTTP_CODE), 'HTTP code is OK');
        $multi->remove_handle($easy);
    }
} while ($running);

done_testing(3 * $n);
