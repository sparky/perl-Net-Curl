package WWW::Curl;

use strict;
use warnings;
use Net::Curl ();

our $VERSION = 4.15;

# copies constants to current namespace
sub _copy_constants
{
	my $EXPORT = shift;
	my $dest = (shift) . "::";
	my $source = shift;

	no strict 'refs';
	my @constants = grep /^CURL/, keys %{ "$source" };
	push @$EXPORT, @constants;

	foreach my $name ( @constants ) {
		*{ $dest . $name } = \*{ $source . $name };
	}
}

1;
