package WWW::CurlOO::Easy;
use strict;
use warnings;

use WWW::CurlOO ();
use Exporter ();

*VERSION = \*WWW::CurlOO::VERSION;

our @ISA = qw(Exporter);
our @EXPORT_OK = grep /^CURL/, keys %{WWW::CurlOO::Easy::};
our %EXPORT_TAGS = ( constants => \@EXPORT_OK );

package WWW::CurlOO::Easy::Code;

use overload
	'0+' => sub {
		return ${(shift)};
	},
	'""' => sub {
		return WWW::CurlOO::Easy::strerror( ${(shift)} );
	},
	fallback => 1;

1;

__END__

=head1 NAME

WWW::CurlOO::Easy - Perl interface for curl_easy_* functions

=head1 WARNING

B<THIS MODULE IS UNDER HEAVY DEVELOPEMENT AND SOME INTERFACE MAY CHANGE YET.>

=head1 SYNOPSIS

 use WWW::CurlOO::Easy qw(:constants);

 my $easy = WWW::CurlOO::Easy->new();
 $easy->setopt( CURLOPT_URL, "http://example.com/" );

 $easy->perform();

=head1 DESCRIPTION

This module wraps easy handle from libcurl and all related functions and
constants. It does not export by default anything, but constants can be
exported upon request.

 use WWW::CurlOO::Easy qw(:constants);

=head1 METHODS

=over

=item CLASS->new( [BASE] )

Creates new WWW::CurlOO::Easy object. If BASE is specified it will be used
as object base, otherwise an empty hash will be used. BASE must be a valid
reference which has not been blessed already. It will not be used by the
object.

Calls L<curl_easy_init(3)> and presets some defaults.

=item OBJECT->duphandle( [BASE] )

Clone WWW::CurlOO::Easy object. It will not copy BASE from the source object.
If you want it copied you must do it on your own.

 use WWW::CurlOO::Easy;
 use Storable qw(dclone);

 my $shallow_clone = $easy->duphandle( { %$easy } );
 my $deep_clone = $easy->duphandle( dclone( $easy ) );

Calls L<curl_easy_duphandle(3)>.

=item OBJECT->setopt( OPTION, VALUE )

Set an option. OPTION is a numeric value, use one of CURLOPT_* constants.
VALUE depends on whatever that option expects.

Calls L<curl_easy_setopt(3)>.

=item OBJECT->pushopt( OPTION, ARRAY )

If option expects a slist, specified array will be appended instead of
replacing the old slist.

Calls L<curl_easy_setopt(3)>.

=item OBJECT->perform( )

Perform upload and download process.

Calls L<curl_easy_perform(3)>.

=item OBJECT->getinfo( OPTION )

Retrieve a value. OPTION is one of C<CURLINFO_*> constants.

Calls L<curl_easy_getinfo(3)>.

=item OBJECT->error( )

Get last error message.

See information on C<CURLOPT_ERRORBUFFER> in L<curl_easy_setopt(3)> for
a longer description.

=item OBJECT->send( BUFFER )

Send raw data.

Calls L<curl_easy_send(3)>. Not available in curl before 7.18.2.

=item OBJECT->recv( BUFFER, MAXLENGTH )

Receive raw data.

Calls L<curl_easy_recv(3)>. Not available in curl before 7.18.2.

=item OBJECT->DESTROY( )

Cleans up. It should not be called manually.

Calls L<curl_easy_cleanup(3)>.

=back

=head1 FUNCTIONS

=over

=item strerror( [WHATEVER], CODE )

Return a string for error code CODE.

Calls L<curl_easy_strerror(3)>.

=back

=head1 SEE ALSO

L<WWW::CurlOO>
L<WWW::CurlOO::Multi>

=head1 COPYRIGHT

Copyright (c) 2011 Przemyslaw Iskra <sparky at pld-linux.org>.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.
