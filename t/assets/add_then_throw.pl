#!/usr/bin/perl

use strict;
use warnings;

use Net::Curl::Multi;
use Net::Curl::Easy qw(:constants);

my $multi = Net::Curl::Multi->new();

my $self = { multi => $multi };

$multi->setopt( Net::Curl::Multi::CURLMOPT_TIMERFUNCTION(), \&_cb_timer );
$multi->setopt( Net::Curl::Multi::CURLMOPT_TIMERDATA(), $self );

sub _cb_timer { 0 }

$multi->setopt( Net::Curl::Multi::CURLMOPT_SOCKETFUNCTION, \&_socket_fn );

sub _socket_fn { 0 }

my $handle = Net::Curl::Easy->new();

$multi->add_handle($handle);

close *STDERR;

die "ohno";

END {
    $? = 42;
}
