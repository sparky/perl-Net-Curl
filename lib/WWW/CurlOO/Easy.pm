package WWW::CurlOO::Easy;
use strict;
use warnings;

use WWW::CurlOO ();
use Exporter 'import';

*VERSION = \*WWW::CurlOO::VERSION;

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

=head2 CONSTRUCTOR

=over

=item new( [BASE] )

Creates new WWW::CurlOO::Easy object. If BASE is specified it will be used
as object base, otherwise an empty hash will be used. BASE must be a valid
reference which has not been blessed already. It will not be used by the
object.

 my $easy = WWW::CurlOO::Easy->new( [qw(my very private data)] );

Calls L<curl_easy_init(3)> and presets some defaults.

=back

=head2 METHODS

=over

=item duphandle( [BASE] )

Clone WWW::CurlOO::Easy object. It will not copy BASE from the source object.
If you want it copied you must do it on your own.

 my $hash_clone = $easy->duphandle( { %$easy } );

 use Storable qw(dclone);
 my $deep_clone = $easy->duphandle( dclone( $easy ) );

Calls L<curl_easy_duphandle(3)>.

=item setopt( OPTION, VALUE )

Set an option. OPTION is a numeric value, use one of CURLOPT_* constants.
VALUE depends on whatever that option expects.

 $easy->setopt( WWW::CurlOO::Easy::CURLOPT_URL, $uri );

Calls L<curl_easy_setopt(3)>.

=item pushopt( OPTION, ARRAYREF )

If option expects a slist, specified array will be appended instead of
replacing the old slist.

 $easy->pushopt( WWW::CurlOO::Easy::CURLOPT_HTTPHEADER, ['More: headers'] );

Builds a slist and calls L<curl_easy_setopt(3)>.

=item perform( )

Perform upload and download process.

 $easy->perform();

Calls L<curl_easy_perform(3)>.

=item getinfo( OPTION )

Retrieve a value. OPTION is one of C<CURLINFO_*> constants.

 my $socket = $self->getinfo( WWW::CurlOO::Easy::CURLINFO_LASTSOCKET );

Calls L<curl_easy_getinfo(3)>.

=item error( )

Get last error message.

See information on C<CURLOPT_ERRORBUFFER> in L<curl_easy_setopt(3)> for
a longer description.

 my $error = $easy->error();
 print "Last error: $error\n";

=item send( BUFFER )

Send raw data.

 $easy->send( $data );

Calls L<curl_easy_send(3)>. Not available in curl before 7.18.2.

=item recv( BUFFER, MAXLENGTH )

B<THIS MAY CHANGE YET>

Receive raw data. Will receive at most MAXLENGTH bytes. New data will be
concatenated to BUFFER.

 $easy->recv( $buffer, $len );

Calls L<curl_easy_recv(3)>. Not available in curl before 7.18.2.

=item multi( )

If easy object is associated with any multi handles, it will return that
multi handle.

 my $multi = $easy->multi;

=item DESTROY( )

Cleans up. It should not be called manually.

Calls L<curl_easy_cleanup(3)>.

=back

=head2 FUNCTIONS

None of those functions are exported, you must use fully qualified names.

=over

=item strerror( [WHATEVER], CODE )

Return a string for error code CODE.

 my $message = WWW::CurlOO::Easy::strerror(
     WWW::CurlOO::Easy::CURLE_OK
 );

Calls L<curl_easy_strerror(3)>.

=back

=head2 CONSTANTS

WWW::CurlOO::Easy contains all the constants that do not form part of any
other WWW::CurlOO modules. List below describes only the ones that behave
differently than their C counterparts.

=over

=item CURLOPT_PRIVATE

setopt() does not allow to use this constant. Hide any private data in your
base object.

=item CURLOPT_ERRORBUFFER

setopt() does not allow to use this constant. You can always retrieve latest
error message with OBJECT->error() method.

=back

=head2 CALLBACKS

Reffer to libcurl documentation for more detailed info on each of those.
Callbacks can be set using setopt() method.

 $easy->setopt( CURLOPT_somethingFUNCTION, \&something );
 $easy->setopt( CURLOPT_somethingDATA, [qw(any additional data you want)] );

=over

=item CURLOPT_WRITEFUNCTION ( CURLOPT_WRITEDATA )

write callback receives 3 arguments: easy object, data to write, and whatever
CURLOPT_WRITEDATA was set to. It must return number of data bytes.

 sub cb_write {
     my ( $easy, $data, $uservar ) = @_;
     # ... process ...
     return CURL_WRITEFUNC_PAUSE if $want_pause;
     return length $data;
 }

=item CURLOPT_READFUNCTION ( CURLOPT_READDATA )

read callback receives 3 arguments: easy object, maximum data length, and
CURLOPT_READDATA value. It must return either a reference to data read or
one of numeric values: 0 - transfer completed, CURL_READFUNC_ABORT - abort
upload, CURL_READFUNC_PAUSE - pause upload. Reference to any value that
is zero in length ("", undef) will also signalize completed transfer.

 sub cb_read {
     my ( $easy, $maxlen, $uservar ) = @_;
     # ... read $data, $maxlen ...
     return \$data;
 }

=item CURLOPT_IOCTLFUNCTION ( CURLOPT_IOCTLDATA )

Not supported yet.

=item CURLOPT_SEEKFUNCTION ( CURLOPT_SEEKDATA ) 7.18.0+

Not supported yet.

=item CURLOPT_SOCKOPTFUNCTION ( CURLOPT_SOCKOPTDATA ) 7.15.6+

Not supported yet.

=item CURLOPT_OPENSOCKETFUNCTION ( CURLOPT_OPENSOCKETDATA ) 7.17.1+

Not supported yet.

=item CURLOPT_PROGRESSFUNCTION ( CURLOPT_PROGRESSDATA )

Progress callback receives 6 arguments: easy object, dltotal, dlnow, ultotal,
ulnow and CURLOPT_PROGRESSDATA value. It should return 0.

 sub cb_progress {
     my ( $easy, $dltotal, $dlnow, $ultotal, $ulnow, $uservar ) = @_;
     # ... display progress ...
     return 0;
 }

=item CURLOPT_HEADERFUNCTION ( CURLOPT_WRITEHEADER )

Behaviour is the same as in write callback.

=item CURLOPT_DEBUGFUNCTION ( CURLOPT_DEBUGDATA )

Debug callback receives 4 arguments: easy object, message type, debug data
and CURLOPT_DEBUGDATA value. Must return 0.

 sub cb_debug {
     my ( $easy, $type, $data, $uservar ) = @_;
     # ... display debug info ...
     return 0;
 }

=item CURLOPT_SSL_CTX_FUNCTION ( CURLOPT_SSL_CTX_DATA )

Not supported, probably will never be.

=item CURLOPT_INTERLEAVEFUNCTION ( CURLOPT_INTERLEAVEDATA ) 7.20.0+

Not supported yet.

=item CURLOPT_CHUNK_BGN_FUNCTION, CURLOPT_CHUNK_END_FUNCTION
    ( CURLOPT_CHUNK_DATA ) 7.21.0+

Not supported yet.

=item CURLOPT_FNMATCH_FUNCTION ( CURLOPT_FNMATCH_DATA ) 7.21.0+

Not supported yet.

=back

=head1 SEE ALSO

L<WWW::CurlOO>
L<WWW::CurlOO::Multi>
L<WWW::CurlOO::examples>
L<libcurl-easy(3)>
L<libcurl-errors(3)>

=head1 COPYRIGHT

Copyright (c) 2011 Przemyslaw Iskra <sparky at pld-linux.org>.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.
