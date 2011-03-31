#!perl
use strict;
use warnings;
use Test::More;

use WWW::CurlOO qw(:constants);
use WWW::CurlOO::Easy qw(:constants);
use WWW::CurlOO::Form qw(:constants);
use WWW::CurlOO::Multi qw(:constants);
use WWW::CurlOO::Share qw(:constants);

WWW::CurlOO::version() =~ m#libcurl/([0-9\.]+)#;
my $cver = eval "v$1";

my @check;
{
	open my $fin, "<", "inc/symbols-in-versions"
	    or die "Cannot open symbols file: $!\n";
	while ( <$fin> ) {
		next if /^#\s+/;
		next if /^\s+/;
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

plan tests => scalar @check;
foreach my $sym ( @check ) {
	my $value;
	eval "\$value = $sym();";
	ok(!$@ && defined($value), "$sym is defined - $@");
}
