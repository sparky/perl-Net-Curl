#!perl
use strict;
use warnings;
use Test::More tests => 7;

use WWW::CurlOO;
use WWW::CurlOO::Easy;
use WWW::CurlOO::Form;
use WWW::CurlOO::Multi;
use WWW::CurlOO::Share;

my %methods = (
	WWW::CurlOO:: => [ qw(version version_info getdate _global_cleanup) ],
	WWW::CurlOO::Easy:: => [ qw(new duphandle setopt pushopt perform
		getinfo error strerror), ],
	WWW::CurlOO::Form:: => [ qw(new add get strerror) ],
	WWW::CurlOO::Multi:: => [ qw(new add_handle remove_handle info_read
		fdset timeout setopt perform socket_action strerror) ],
	WWW::CurlOO::Share:: => [ qw(new setopt strerror) ],
);

my $count = map { @$_ } values %methods;
print "# there are $count functions to test\n";

while ( my ($pkg, $methods) = each %methods ) {
	can_ok( $pkg, @$methods );
}

if ( WWW::CurlOO::LIBCURL_VERSION_NUM() >= 0x071202 ) {
	ok( WWW::CurlOO::Easy->can( "send" ), "Easy has send method" );
	ok( WWW::CurlOO::Easy->can( "recv" ), "Easy has recv method" );
} else {
	ok( ! WWW::CurlOO::Easy->can( "send" ), "Easy does not have send method" );
	ok( ! WWW::CurlOO::Easy->can( "recv" ), "Easy does not have recv method" );
}
