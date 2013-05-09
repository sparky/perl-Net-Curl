#!/usr/bin/perl
use strict;
use warnings qw(all);
use FindBin qw($Bin $Script);

# shamelessly stolen from RJRAY/Perl-RPM-1.51/t/09_leaks.t

BEGIN {
    eval {
        require Devel::Leak;
    };
    if ($@) {
        print "1..0 # Skip Devel::Leak required\n";
        exit 0;
    }
}

use Test::More;

sub test_leak (&$;$) {
    my ($code, $descr, $maxleak) = (@_, ($] >= 5.017) ? 5 : 0);
    my $n1 = Devel::Leak::NoteSV(my $handle);
    $code->() for 1 .. 10_000;
    my $n2 = Devel::Leak::CheckSV($handle);
    cmp_ok($n1 + $maxleak, '>=', $n2, $descr);
}

use Net::Curl qw(:constants);
use Net::Curl::Easy qw(:constants);
use Net::Curl::Form qw(:constants);
use Net::Curl::Multi qw(:constants);
use Net::Curl::Share qw(:constants);

my $easy = Net::Curl::Easy->new;
test_leak { my $easy = Net::Curl::Easy->new or die }
    q(Net::Curl::Easy->new);

my $form = Net::Curl::Form->new;
test_leak { my $form = Net::Curl::Form->new or die }
    q(Net::Curl::Form->new);

my $multi = Net::Curl::Multi->new;
SKIP: {
    skip q(libcurl/7.29.0 crashes here: http://sourceforge.net/p/curl/bugs/1194/), 1
        if Net::Curl::version_info()->{version} eq q(7.29.0);
    test_leak { my $multi = Net::Curl::Multi->new or die }
       q(Net::Curl::Multi->new);
}

my $share = Net::Curl::Share->new;
$share->setopt(CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);
$share->setopt(CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS);
eval { $share->setopt(CURLSHOPT_SHARE, CURL_LOCK_DATA_SSL_SESSION) };
test_leak { my $share = Net::Curl::Share->new or die }
    q(Net::Curl::Share->new);

my $url = $ENV{CURL_TEST_URL};
$url = qq(file://$Bin/$Script)
    if not defined $url or $url;

my $n1 = Devel::Leak::NoteSV(my $handle);
test_leak {
    my $curl = Net::Curl::Easy->new() or die "cannot curl";
    $multi->add_handle($curl);

    $curl->setopt(CURLOPT_NOPROGRESS, 1);
    $curl->setopt(CURLOPT_FOLLOWLOCATION, 1);
    $curl->setopt(CURLOPT_TIMEOUT, 30);

    open(my $head, "+>", undef);
    Net::Curl::Easy::setopt($curl, CURLOPT_WRITEHEADER, $head);
    open(my $body, "+>", undef);
    Net::Curl::Easy::setopt($curl, CURLOPT_WRITEDATA, $body);

    $curl->setopt(CURLOPT_URL, $url);
    $curl->setopt(CURLOPT_SHARE, $share);

    eval { $multi->perform() };
    if (not $@) {
        my $bytes = $curl->getinfo(CURLINFO_SIZE_DOWNLOAD);
        my $realurl = $curl->getinfo(CURLINFO_EFFECTIVE_URL);
        my $httpcode = $curl->getinfo(CURLINFO_HTTP_CODE);
        $multi->remove_handle($curl);
    } else {
        die "not ok " . $curl->error;
    }
} q(old-13slowleak.t);
my $n2 = Devel::Leak::CheckSV($handle);
cmp_ok($n1, '>=', $n2, q(cross-references));

done_testing(6);
