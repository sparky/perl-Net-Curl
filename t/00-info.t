#!perl
use strict;
use warnings;
use Test::More tests => 4;
use WWW::CurlOO;

diag "libcurl\n";
diag "version():\n\t" . WWW::CurlOO::version() . "\n";
my $vi = WWW::CurlOO::version_info();

diag "version_info():\n";
foreach my $key ( sort keys %$vi ) {
	my $value = $vi->{$key};
	if ( $key eq 'features' ) {
		print_features( $value );
		next;
	} elsif ( ref $value and ref $value eq 'ARRAY' ) {
		$value = join ', ', sort @$value;
	} elsif ( $value =~ m/^\d+$/ ) {
		$value = sprintf "0x%06x", $value
			if $value > 255;
	} else {
		$value = "'$value'";
	}
	diag "\t{$key} = $value;\n";
}

sub print_features
{
	my $features = shift;
	my @found = ('');
	my @missing = ('');
	foreach my $f ( sort { WWW::CurlOO->$a() <=> WWW::CurlOO->$b() }
			grep /^CURL_VERSION_/, keys %{WWW::CurlOO::} )
	{
		my $val = WWW::CurlOO->$f();
		my $bit = log ( $val ) / log 2;
		if ( $features & $val ) {
			push @found, "$f (1<<$bit)"
		} else {
			push @missing, "$f (1<<$bit)"
		}
	}

	local $" = "\n\t\t| ";
	diag "\t{features} = @found;\n";
	diag "\tmissing features = @missing;\n";
}

diag "build version:\n";
my @buildtime = qw(
	LIBCURL_COPYRIGHT
	LIBCURL_VERSION
	LIBCURL_VERSION_NUM
	LIBCURL_VERSION_MAJOR
	LIBCURL_VERSION_MINOR
	LIBCURL_VERSION_PATCH
	LIBCURL_TIMESTAMP
);
foreach my $key ( @buildtime ) {
	my $value = WWW::CurlOO->$key();
	if ( $value =~ m/^\d+$/ ) {
		$value = sprintf "0x%06x", $value
			if $value > 255;
	} else {
		$value = "'$value'";
	}

	diag "\t$key = $value\n";
}

# older than this are not supported
cmp_ok( $vi->{age}, '>=', WWW::CurlOO::CURLVERSION_THIRD,
	"{age} >= WWW::CurlOO::CURLVERSION_THIRD" );

# has same version as the one we compiled with
cmp_ok( $vi->{age}, '==', WWW::CurlOO::CURLVERSION_NOW,
	"{age} == WWW::CurlOO::CURLVERSION_NOW" );

is( $vi->{version}, WWW::CurlOO::LIBCURL_VERSION,
	"{version} eq WWW::CurlOO::LIBCURL_VERSION" );

cmp_ok( $vi->{version_num}, '==', WWW::CurlOO::LIBCURL_VERSION_NUM,
	"{version_num} == WWW::CurlOO::LIBCURL_VERSION_NUM" );
