#!perl
use strict;
use warnings;
use Test::More tests => 2;

use Net::Curl;
use Net::Curl::Easy;
use Net::Curl::Form;
use Net::Curl::Multi;
use Net::Curl::Share;

subtest methods => sub {
    my %methods = (
        Net::Curl:: => [ qw(version version_info getdate) ],
        Net::Curl::Easy:: => [ qw(new duphandle setopt pushopt perform
            getinfo error strerror form multi reset share), ],
        Net::Curl::Form:: => [ qw(new add get strerror) ],
        Net::Curl::Multi:: => [ qw(new add_handle remove_handle info_read
            fdset timeout setopt perform socket_action strerror handles) ],
        Net::Curl::Share:: => [ qw(new setopt strerror) ],
    );

    while ( my ($pkg, $methods) = each %methods ) {
        subtest $pkg => sub {
            ok $pkg->can($_), $_ for @$methods;
        };
    }
};

subtest "version-dependent methods" => sub {
    my $libcurl_version = Net::Curl::LIBCURL_VERSION_NUM();
    diag 'LIBCURL_VERSION: ', $libcurl_version;

    my @version_methods = (
        [ 'Net::Curl::Multi', 'wait', 0x071C00 ],
        [ 'Net::Curl::Multi', 'assign', 0x070F05 ],
        [ 'Net::Curl::Easy', 'pause', 0x071200 ],
        [ 'Net::Curl::Easy', 'send', 0x071202 ],
        [ 'Net::Curl::Easy', 'recv', 0x071202 ],
    );

    for ( @version_methods ) {
        my( $package, $method, $min_version ) = @$_;
        my $should_have = $libcurl_version >= $min_version;
        my $prefix = $should_have ? 'has ' : "hasn't ";
        my $message = $prefix . join( '::', $package, $method ) . " - $min_version";

        is !!$package->can( $method ) => $should_have, $message;
    }
};
