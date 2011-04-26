#!perl
use strict;
use warnings;
use Test::More tests => 9;

use WWW::CurlOO;
use WWW::CurlOO::Easy;
use WWW::CurlOO::Form;
use WWW::CurlOO::Multi;
use WWW::CurlOO::Share;

my %methods = (
	WWW::CurlOO:: => [ qw(version version_info getdate) ],
	WWW::CurlOO::Easy:: => [ qw(new duphandle setopt pushopt perform
		getinfo error strerror form multi reset share), ],
	WWW::CurlOO::Form:: => [ qw(new add get strerror) ],
	WWW::CurlOO::Multi:: => [ qw(new add_handle remove_handle info_read
		fdset timeout setopt perform socket_action strerror handles) ],
	WWW::CurlOO::Share:: => [ qw(new setopt strerror) ],
);

my $count = map { @$_ } values %methods;
print "# there are $count functions to test\n";

while ( my ($pkg, $methods) = each %methods ) {
	can_ok( $pkg, @$methods );
}

if ( WWW::CurlOO::LIBCURL_VERSION_NUM() >= 0x070F05 ) {
	ok( WWW::CurlOO::Multi->can( "assign" ), "Multi has assign method" );
} else {
	ok( ! WWW::CurlOO::Multi->can( "assign" ), "Multi does not have assign method" );
}
if ( WWW::CurlOO::LIBCURL_VERSION_NUM() >= 0x071200 ) {
	ok( WWW::CurlOO::Easy->can( "pause" ), "Easy has pause method" );
} else {
	ok( ! WWW::CurlOO::Easy->can( "pause" ), "Easy does not have pause method" );
}
if ( WWW::CurlOO::LIBCURL_VERSION_NUM() >= 0x071202 ) {
	ok( WWW::CurlOO::Easy->can( "send" ), "Easy has send method" );
	ok( WWW::CurlOO::Easy->can( "recv" ), "Easy has recv method" );
} else {
	ok( ! WWW::CurlOO::Easy->can( "send" ), "Easy does not have send method" );
	ok( ! WWW::CurlOO::Easy->can( "recv" ), "Easy does not have recv method" );
}
