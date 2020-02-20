#!/usr/bin/perl

use strict;
use warnings;

die "ohno";

END {
    $? = 42;
}
