#!/usr/bin/perl

use strict;
use warnings;

use FindBin;

use Test::More;

system $^X, "$FindBin::Bin/assets/add_then_throw.pl";

if ($? != (42 << 8)) {
    require Config;
    plan skip_all => "This perl ($Config::Config{'version'}) doesn’t appear to set exit value from \$? in END.\n";
}

plan tests => 1;

my @inc_args = map { ('-I', $_) } @INC;

system $^X, @inc_args, "$FindBin::Bin/assets/add_then_throw.pl";

is( $?, (42 << 8), 'exception did not cause segfault' );
