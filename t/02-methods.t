#!perl
use strict;
use warnings;
use Test::More tests => 10;

use Net::Curl;
use Net::Curl::Easy;
use Net::Curl::Form;
use Net::Curl::Multi;
use Net::Curl::Share;

my %methods = (
	Net::Curl:: => [ qw(version version_info getdate) ],
	Net::Curl::Easy:: => [ qw(new duphandle setopt pushopt perform
		getinfo error strerror form multi reset share), ],
	Net::Curl::Form:: => [ qw(new add get strerror) ],
	Net::Curl::Multi:: => [ qw(new add_handle remove_handle info_read
		fdset timeout setopt perform socket_action strerror handles) ],
	Net::Curl::Share:: => [ qw(new setopt strerror) ],
);

my $count = map { @$_ } values %methods;
print "# there are $count functions to test\n";

while ( my ($pkg, $methods) = each %methods ) {
	can_ok( $pkg, @$methods );
}

if ( Net::Curl::LIBCURL_VERSION_NUM() >= 0x071C00 ) {
	ok( Net::Curl::Multi->can( "wait" ), "Multi has wait method" );
} else {
	ok( ! Net::Curl::Multi->can( "wait" ), "Multi does not have wait method" );
}
if ( Net::Curl::LIBCURL_VERSION_NUM() >= 0x070F05 ) {
	ok( Net::Curl::Multi->can( "assign" ), "Multi has assign method" );
} else {
	ok( ! Net::Curl::Multi->can( "assign" ), "Multi does not have assign method" );
}
if ( Net::Curl::LIBCURL_VERSION_NUM() >= 0x071200 ) {
	ok( Net::Curl::Easy->can( "pause" ), "Easy has pause method" );
} else {
	ok( ! Net::Curl::Easy->can( "pause" ), "Easy does not have pause method" );
}
if ( Net::Curl::LIBCURL_VERSION_NUM() >= 0x071202 ) {
	ok( Net::Curl::Easy->can( "send" ), "Easy has send method" );
	ok( Net::Curl::Easy->can( "recv" ), "Easy has recv method" );
} else {
	ok( ! Net::Curl::Easy->can( "send" ), "Easy does not have send method" );
	ok( ! Net::Curl::Easy->can( "recv" ), "Easy does not have recv method" );
}
