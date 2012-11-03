#!/usr/bin/perl
use strict;
use warnings qw(all);

# shamelessly stolen from RJRAY/Perl-RPM-1.51/t/09_leaks.t

BEGIN {
    eval {
        require Devel::Leak;
        require Test::More;
    };
    if ($@) {
        print "1..0 # Skip Devel::Leak and Test::More required\n";
        exit 0;
    }
}

use Test::More;

sub test_leak (&$;$) {
    my ($code, $descr, $maxleak) = (@_, 0);
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
test_leak { my $multi = Net::Curl::Multi->new or die }
    q(Net::Curl::Multi->new);

my $share = Net::Curl::Share->new;
test_leak { my $share = Net::Curl::Share->new or die }
    q(Net::Curl::Share->new);

done_testing(4);
