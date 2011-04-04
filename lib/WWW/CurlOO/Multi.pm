package WWW::CurlOO::Multi;
use strict;
use warnings;

use WWW::CurlOO ();
use Exporter ();

*VERSION = \*WWW::CurlOO::VERSION;

our @ISA = qw(Exporter);
our @EXPORT_OK = grep /^CURL/, keys %{WWW::CurlOO::Multi::};
our %EXPORT_TAGS = ( constants => \@EXPORT_OK );

1;
