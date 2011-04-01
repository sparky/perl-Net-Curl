#!perl
use strict;
use warnings;
use Test::More tests => 2;
use WWW::CurlOO;

warn "libcurl\n";
warn "version():\n\t" . WWW::CurlOO::version() . "\n";
my $vi = WWW::CurlOO::version_info();

warn "version_info():\n";
foreach my $key ( sort keys %$vi ) {
	my $value = $vi->{$key};
	if ( $key eq 'features' ) {
		print_features( $value );
		next;
	} elsif ( ref $value and ref $value eq 'ARRAY' ) {
		$value = join ', ', sort @$value;
	} elsif ( $value =~ m/^\d+$/ ) {
		$value = sprintf "0x%06x", $value
			if $value > 15;
	} else {
		$value = "'$value'";
	}
	warn "\t{$key} = $value;\n";
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
	warn "\t{features} = @found;\n";
	warn "\tmissing features = @missing;\n";
}

# older than this are not supported
ok( $vi->{age} >= WWW::CurlOO::CURLVERSION_THIRD, "age ($vi->{age}) >= WWW::CurlOO::CURLVERSION_THIRD" );

# has same version as the one we compiled with
ok( $vi->{age} == WWW::CurlOO::CURLVERSION_NOW, "age ($vi->{age}) == WWW::CurlOO::CURLVERSION_NOW" );
