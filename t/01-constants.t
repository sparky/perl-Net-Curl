#!perl
use strict;
use warnings;
use Test::More;

use Net::Curl qw(:constants);
use Net::Curl::Easy qw(:constants);
use Net::Curl::Form qw(:constants);
use Net::Curl::Multi qw(:constants);
use Net::Curl::Share qw(:constants);

Net::Curl::version() =~ m#libcurl/([0-9\.]+)#;
my $cver = eval "v$1";

my @check;
{
	open my $fin, "<", "inc/symbols-in-versions"
	    or die "Cannot open symbols file: $!\n";
	while ( <$fin> ) {
		next if /^[#\s]/;
		my ( $sym, $in, $dep, $out ) = split /\s+/, $_;

		if ( $out ) {
			my $vout = eval "v$out";
			next if $cver ge $vout;
		}

		if ( $in ne "-" ) {
			my $vin = eval "v$in";
			next unless $cver ge $vin;
		}

		push @check, $sym;
	}
}

push @check, qw(
	LIBCURL_VERSION_NUM
	LIBCURL_VERSION_MAJOR
	LIBCURL_VERSION_MINOR
	LIBCURL_VERSION_PATCH
);


plan tests => 10 + 3 * scalar @check;
cmp_ok( scalar ( @check ), '>=', 300, 'at least 300 symbols' );

foreach my $sym ( @check ) {
	my $value;
	eval "\$value = $sym();";
	is( $@, "", "$sym constant can be retrieved" );
	ok( defined( $value ), "$sym is defined");
	like( $value, qr/^-?\d+$/, "$sym value is an integer" );
}

{
	my $value;
	eval { $value = LIBCURL_COPYRIGHT() };
	is( $@, "", 'LIBCURL_COPYRIGHT constant can be retrieved' );
	ok( defined( $value ), "LIBCURL_COPYRIGHT is defined");
	like( $value, qr/[a-z]/i, 'LIBCURL_COPYRIGHT is a string' );
}
{
	my $value;
	eval { $value = LIBCURL_TIMESTAMP() };
	is( $@, "", 'LIBCURL_TIMESTAMP constant can be retrieved' );
	ok( defined( $value ), "LIBCURL_TIMESTAMP is defined");
	# Format changed over time in /usr/include/curl/curlver.h
	# libcurl-devel-7.37.0-16.3.1:
	#   #define LIBCURL_TIMESTAMP "Wed May 21 05:58:26 UTC 2014"
	# libcurl-devel-7.54.1-1.2:
	#   #define LIBCURL_TIMESTAMP "2017-06-14"
	like( $value, qr/\b[0-9]{4}\b/i, 'LIBCURL_TIMESTAMP is a string' );
}
{
	my $value;
	eval { $value = LIBCURL_VERSION() };
	is( $@, "", 'LIBCURL_VERSION constant can be retrieved' );
	ok( defined( $value ), "LIBCURL_VERSION is defined");
	like( $value, qr/^7\.\d{2}\.\d{1,2}(-.*)?$/, 'LIBCURL_VERSION is correct' );
}
