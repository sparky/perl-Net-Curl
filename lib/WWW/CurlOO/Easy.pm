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

 $easy->pushopt( WWW::CurlOO::Easy::CURLOPT_HTTPHEADER,
     ['More: headers'] );

Builds a slist and calls L<curl_easy_setopt(3)>.

=item perform( )

Perform upload and download process.

 $easy->perform();

Calls L<curl_easy_perform(3)>.

=item getinfo( OPTION )

Retrieve a value. OPTION is one of C<CURLINFO_*> constants.

 my $socket = $self->getinfo( CURLINFO_LASTSOCKET );

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

Receive raw data. Will receive at most MAXLENGTH bytes. New data will be
concatenated to BUFFER.

 $easy->recv( $buffer, $len );

Calls L<curl_easy_recv(3)>. Not available in curl before 7.18.2.

=item multi( )

If easy object is associated with any multi handles, it will return that
multi handle.

 my $multi = $easy->multi;

=item share( )

If share object is attached to this easy handle, this method will return that
share object.

 my $share = $easy->share;

=item form( )

If form object is attached to this easy handle, this method will return that
form object.

 my $form = $easy->form;

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
 $easy->setopt( CURLOPT_somethingDATA, [qw(any additional data
     you want)] );

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

ioctl callback receives 3 arguments: easy object, ioctl command, and
CURLOPT_IOCTLDATA value. It must return a curlioerr value.

 sub cb_ioctl {
     my ( $easy, $command, $uservar ) = @_;

     if ( $command == CURLIOCMD_RESTARTREAD ) {
         if ( restart_read() ) {
             return CURLIOE_OK;
         } else {
             return CURLIOE_FAILRESTART;
         }
     }
     return CURLIOE_UNKNOWNCMD;
 }

=item CURLOPT_SEEKFUNCTION ( CURLOPT_SEEKDATA ) 7.18.0+

seek callback receives 4 arguments: easy object, offset / position,
origin / whence, and CURLOPT_SEEKDATA value. Must return one of
CURL_SEEKFUNC_* values.

 use Fcntl qw(:seek);
 sub cb_seek {
     my ( $easy, $offset, $origin, $uservar ) = @_;
     if ( $origin = SEEK_SET ) {
         if ( seek SOMETHING, $offset, SEEK_SET ) {
             return CURL_SEEKFUNC_OK;
         }
         return CURL_SEEKFUNC_CANTSEEK;
     }
     return CURL_SEEKFUNC_FAIL
 }

=item CURLOPT_SOCKOPTFUNCTION ( CURLOPT_SOCKOPTDATA ) 7.15.6+

sockopt callback receives 4 arguments: easy object, socket fd, socket purpose,
and CURLOPT_SOCKOPTDATA value. Should return 0 on success.

 sub cb_sockopt {
     my ( $easy, $socket, $purpose, $uservar ) = @_;
     # ... do something with the socket ...
     return 0;
 }

=item CURLOPT_OPENSOCKETFUNCTION ( CURLOPT_OPENSOCKETDATA ) 7.17.1+

opensocket callback receives 4 arguments: easy object, socket purpose,
address structure (in form of a hashref), and CURLOPT_OPENSOCKETDATA value.
The address structure has following numeric values: "family", "socktype",
"protocol", "addrlen"; and "addr" in binary form. Use Socket CPAN module to
decode "addr" field.

 use Socket;
 sub cb_opensocket {
     my ( $easy, $purpose, $address, $uservar ) = @_;
     my $addr = unpack_sockaddr_in( $address->{addr} );
     # ... open ...
     return $socket;
 }

Currently WWW::CurlOO does not honour any changes made to $address, this
may be fixed some day.

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

Behaviour is the same as in write callback.

=item CURLOPT_CHUNK_BGN_FUNCTION ( CURLOPT_CHUNK_DATA ) 7.21.0+

chunk_bgn callback receives 4 arguments: easy object, fileinfo structure (in
form of a hashref), number of remaining chunks, and CURLOPT_CHUNK_DATA value.
It must return one of CURL_CHUNK_BGN_FUNC_* values.

 sub cb_chunk_bgn {
     my ( $easy, $fileinfo, $remaining, $uservar ) = @_;

     if ( exists $fileinfo->{filetype} and
             $fileinfo->{filetype} != CURLFILETYPE_FILE ) {
         # download regular files only
         return CURL_CHUNK_BGN_FUNC_SKIP;
     }
     my $filename = "unknown." . $remaining;
     $filename = $fileinfo->{filename}
         if defined $fileinfo->{filename};

     open $easy->{myfile}, '>', $filename
         or return CURL_CHUNK_BGN_FUNC_FAIL;

     return CURL_CHUNK_BGN_FUNC_OK;
 }

=item CURLOPT_CHUNK_END_FUNCTION ( CURLOPT_CHUNK_DATA ) 7.21.0+

chunk_end callback receives 2 arguments: easy object and CURLOPT_CHUNK_DATA
value. Must return one of CURL_CHUNK_END_FUNC_* values.

 sub cb_chunk_end {
     my ( $easy, $uservar ) = @_;
     # ... close $easy-{myfile} ...
     return CURL_CHUNK_END_FUNC_OK;
 }

=item CURLOPT_FNMATCH_FUNCTION ( CURLOPT_FNMATCH_DATA ) 7.21.0+

fnmatch callback receives 4 arguments: easy object, pattern, string, and
CURLOPT_FNMATCH_DATA value. Must return one of CURL_FNMATCHFUNC_* values.

 sub cb_fnmatch {
     my ( $easy, $pattern, $string, $uservar ) = @_;
     return ( $string =~ m/$pattern/i
         ? CURL_FNMATCHFUNC_MATCH
         : CURL_FNMATCHFUNC_NOMATCH );
 }

=back

=head1 SEE ALSO

L<WWW::CurlOO>
L<WWW::CurlOO::Multi>
L<WWW::CurlOO::examples(3pm)>
L<libcurl-easy(3)>
L<libcurl-errors(3)>

=head1 COPYRIGHT

Copyright (c) 2011 Przemyslaw Iskra <sparky at pld-linux.org>.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.
