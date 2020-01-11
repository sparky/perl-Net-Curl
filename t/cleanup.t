#!/usr/bin/perl

use strict;
use warnings;

use FindBin;

use Test::More tests => 1;

my @inc_args = map { ('-I', $_) } @INC;

system $^X, @inc_args, "$FindBin::Bin/assets/add_then_throw.pl";

is( $?, (42 << 8), 'exception did not cause segfault' );
