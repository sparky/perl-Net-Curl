package WWW::CurlOO::Easy;
use strict;
use warnings;

use WWW::CurlOO ();
use Exporter ();

our @ISA = qw(Exporter);
our @EXPORT_OK = grep /^CURL/, keys %{WWW::CurlOO::Easy::};
our %EXPORT_TAGS = ( constants => \@EXPORT_OK );

1;
