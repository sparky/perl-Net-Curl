#!/usr/bin/perl

use strict;
use warnings;

use Net::Curl::Multi;
use Net::Curl::Easy;

close *STDERR;
open STDERR, '>>&=' . fileno(STDOUT);

my $multi = Net::Curl::Multi->new();
my $easy = Net::Curl::Easy->new();

$multi->add_handle($easy);
undef $multi;
