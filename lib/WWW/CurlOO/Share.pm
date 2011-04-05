package WWW::CurlOO::Share;
use strict;
use warnings;

use WWW::CurlOO ();
use Exporter ();

*VERSION = \*WWW::CurlOO::VERSION;

our @ISA = qw(Exporter);
our @EXPORT_OK = grep /^CURL/, keys %{WWW::CurlOO::Share::};
our %EXPORT_TAGS = ( constants => \@EXPORT_OK );

package WWW::CurlOO::Share::Code;

use overload
	'0+' => sub {
		return ${(shift)};
	},
	'""' => sub {
		return WWW::CurlOO::Share::strerror( ${(shift)} );
	},
	fallback => 1;

1;

__END__

=head1 NAME

WWW::CurlOO::Share - Perl interface for curl_share_* functions

=head1 WARNING

B<THIS MODULE IS UNDER HEAVY DEVELOPEMENT AND SOME INTERFACE MAY CHANGE YET.>

=head1 SYNOPSIS

 use WWW::CurlOO::Share qw(:constants);

 my $share = WWW::CurlOO::Share->new();
 $share->setopt( CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE );

 $easy1->setopt( CURLOPT_SHARE() => $share );
 $easy2->setopt( CURLOPT_SHARE() => $share );

=head1 DESCRIPTION

This module wraps share handle from libcurl and all related functions and
constants. It does not export by default anything, but constants can be
exported upon request.

 use WWW::CurlOO::Share qw(:constants);

=head1 METHODS

=over

=item CLASS->new( [BASE] )

Creates new WWW::CurlOO::Share object. If BASE is specified it will be used
as object base, otherwise an empty hash will be used. BASE must be a valid
reference which has not been blessed already. It will not be used by the
object.

Calls L<curl_share_init(3)>.

=item OBJECT->setopt( OPTION, VALUE )

Set an option. OPTION is a numeric value, use one of CURLSHOPT_* constants.
VALUE depends on whatever that option expects.

Calls L<curl_share_setopt(3)>.

=item OBJECT->DESTROY( )

Cleans up. It should not be called manually.

Calls L<curl_share_cleanup(3)>.

=back

=head1 FUNCTIONS

=over

=item strerror( [WHATEVER], CODE )

Return a string for error code CODE.

See L<curl_share_strerror(3)> for more info.

=back

=head1 SEE ALSO

L<WWW::CurlOO>
L<WWW::CurlOO::Easy>
L<WWW::CurlOO::Multi>

=head1 COPYRIGHT

Copyright (c) 2011 Przemyslaw Iskra <sparky at pld-linux.org>.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.
