#!perl
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 2;
use WWW::CurlOO;
$Data::Dumper::Quotekeys = 0;

warn "libcurl\n";
warn "version():\n\t" . WWW::CurlOO::version() . "\n";
my $vi = WWW::CurlOO::version_info();
warn "version_info():\n" . Data::Dumper->Dump( [$vi], ["vi"] );
warn "{version_num} = " . sprintf "0x%06x\n", $vi->{version_num};
warn "{ares_num} = " . sprintf "0x%06x\n", $vi->{ares_num};

{
	my @found;
	my @missing;
	foreach my $f ( sort { WWW::CurlOO->$a() <=> WWW::CurlOO->$b() }
			grep /^CURL_VERSION_/, keys %{WWW::CurlOO::} )
	{
		my $val = WWW::CurlOO->$f();
		my $bit = log ( $val ) / log 2;
		if ( $vi->{features} & $val ) {
			push @found, "$f (1<<$bit)"
		} else {
			push @missing, "$f (1<<$bit)"
		}
	}

	local $" = "\n\t| ";
	warn "{features} = @found;\n";
	warn "missing features = @missing;\n";
}

# older than this are not supported
ok( $vi->{age} >= WWW::CurlOO::CURLVERSION_THIRD, "age ($vi->{age}) >= WWW::CurlOO::CURLVERSION_THIRD" );

# has same version as the one we compiled with
ok( $vi->{age} == WWW::CurlOO::CURLVERSION_NOW, "age ($vi->{age}) == WWW::CurlOO::CURLVERSION_NOW" );
