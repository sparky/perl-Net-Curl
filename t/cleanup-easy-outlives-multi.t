#!/usr/bin/perl

use strict;
use warnings;

use FindBin;

use Test::More;

plan tests => 2;

my $out = open my $rfh, '-|', "$^X $FindBin::Bin/assets/easy_outlives_multi.pl";
my $got = do { local $/; readline $rfh };
close $rfh;

is( $?, 0, 'no error when easy outlives its multi at global destruction' );

is( $got, q<>, '… and nothing was output' );
