package Net::Curl::Easy;
use strict;
use warnings;

use Net::Curl ();
use Exporter 'import';

our $VERSION = '0.50';

our @EXPORT_OK = grep { /^CURL/x } keys %{Net::Curl::Easy::};
our %EXPORT_TAGS = ( constants => \@EXPORT_OK );

## no critic (ProhibitMultiplePackages)
package Net::Curl::Easy::Code;

use overload
	'0+' => sub {
		return ${(shift)};
	},
	'""' => sub {
		return Net::Curl::Easy::strerror( ${(shift)} );
	},
	fallback => 1;

1;

__END__

=head1 NAME

Net::Curl::Easy - Perl interface for curl_easy_* functions

=head1 SYNOPSIS

Direct use.

 use Net::Curl::Easy qw(:constants);

 my $easy = Net::Curl::Easy->new();
 $easy->setopt( CURLOPT_URL, "http://example.com/" );

 $easy->perform();

Build your own browser.

 package MyBrowser;
 use Net::Curl::Easy qw(/^CURLOPT_/ /^CURLINFO_/);
 use base qw(Net::Curl::Easy);

 sub new
 {
     my $class = shift;
     my $self = $class->SUPER::new( { head => '', body => ''} );
     $self->setopt( CURLOPT_USERAGENT, "MyBrowser v0.1" );
     $self->setopt( CURLOPT_FOLLOWLOCATION, 1 );
     $self->setopt( CURLOPT_COOKIEFILE, "" ); # enable cookie session
     $self->setopt( CURLOPT_FILE, \$self->{body} );
     $self->setopt( CURLOPT_HEADERDATA, \$self->{head} );
     return $self;
 }

 sub get
 {
     my ( $self, $uri ) = @_;
     $self->setopt( CURLOPT_URL, $uri );
     @$self{qw(head body)} = ('', '');
     $self->perform();
     my $ref = $self->getinfo( CURLINFO_EFFECTIVE_URL );
     $self->setopt( CURLOPT_REFERER, $ref );
     return @$self{qw(head body)};
 }

=head1 DESCRIPTION

This module wraps easy handle from libcurl and all related functions and
constants. It does not export by default anything, but constants can be
exported upon request.

 use Net::Curl::Easy qw(:constants);

=head2 CONSTRUCTOR

=over

=item new( [BASE] )

Creates new Net::Curl::Easy object. If BASE is specified it will be used
as object base, otherwise an empty hash will be used. BASE must be a valid
reference which has not been blessed already. It will not be used by the
object.

 my $easy = Net::Curl::Easy->new( [qw(my very private data)] );

Calls L<curl_easy_init(3)|https://curl.haxx.se/libcurl/c/curl_easy_init.html> and presets some defaults.

=back

=head2 METHODS

=over

=item duphandle( [BASE] )

Clone Net::Curl::Easy object. It will not copy BASE from the source object.
If you want it copied you must do it on your own.

 my $hash_clone = $easy->duphandle( { %$easy } );

 use Storable qw(dclone);
 my $deep_clone = $easy->duphandle( dclone( $easy ) );

Calls L<curl_easy_duphandle(3)|https://curl.haxx.se/libcurl/c/curl_easy_duphandle.html>.

=item setopt( OPTION, VALUE )

Set an option. OPTION is a numeric value, use one of CURLOPT_* constants.
VALUE depends on whatever that option expects.

 $easy->setopt( Net::Curl::Easy::CURLOPT_URL, $uri );

Calls L<curl_easy_setopt(3)|https://curl.haxx.se/libcurl/c/curl_easy_setopt.html>. Throws L</Net::Curl::Easy::Code> on error.

=item pushopt( OPTION, ARRAYREF )

If option expects a slist, specified array will be appended instead of
replacing the old slist.

 $easy->pushopt( Net::Curl::Easy::CURLOPT_HTTPHEADER,
     ['More: headers'] );

Builds a slist and calls L<curl_easy_setopt(3)|https://curl.haxx.se/libcurl/c/curl_easy_setopt.html>.
Throws L</Net::Curl::Easy::Code> on error.

=item reset( )

Reinitializes easy handle B<(was broken before v0.27!)>.

 $easy->reset();

Calls L<curl_easy_reset(3)|https://curl.haxx.se/libcurl/c/curl_easy_reset.html> and presets some defaults.

=item perform( )

Perform upload and download process.

 $easy->perform();

Calls L<curl_easy_perform(3)|https://curl.haxx.se/libcurl/c/curl_easy_perform.html>. Rethrows exceptions from callbacks.
Throws L</Net::Curl::Easy::Code> on other errors.

=item getinfo( OPTION )

Retrieve a value. OPTION is one of C<CURLINFO_*> constants.

 my $socket = $self->getinfo( CURLINFO_LASTSOCKET );

Calls L<curl_easy_getinfo(3)|https://curl.haxx.se/libcurl/c/curl_easy_getinfo.html>.
Throws L</Net::Curl::Easy::Code> on error.

In the case of C<CURLINFO_CERTINFO>, the return is an array reference of
hash references; each hash represents one certificate.

=item pause( )

Pause the transfer.

Calls L<curl_easy_pause(3)|https://curl.haxx.se/libcurl/c/curl_easy_pause.html>. Not available in curl before 7.18.0.
Throws L</Net::Curl::Easy::Code> on error.

=item send( BUFFER )

Send raw data.

 $easy->send( $data );

Calls L<curl_easy_send(3)|https://curl.haxx.se/libcurl/c/curl_easy_send.html>. Not available in curl before 7.18.2.
Throws L</Net::Curl::Easy::Code> on error.

=item recv( BUFFER, MAXLENGTH )

Receive raw data. Will receive at most MAXLENGTH bytes. New data will be
concatenated to BUFFER.

 $easy->recv( $buffer, $len );

Calls L<curl_easy_recv(3)|https://curl.haxx.se/libcurl/c/curl_easy_recv.html>. Not available in curl before 7.18.2.
Throws L</Net::Curl::Easy::Code> on error.

=item error( )

Get last error message.

See information on C<CURLOPT_ERRORBUFFER> in L<curl_easy_setopt(3)|https://curl.haxx.se/libcurl/c/curl_easy_setopt.html> for
a longer description.

 my $error = $easy->error();
 print "Last error: $error\n";

=item multi( )

If easy object is associated with any multi handles, it will return that
multi handle.

 my $multi = $easy->multi;

Use $multi->add_handle() to attach the easy object to the multi interface.

=item share( )

If share object is attached to this easy handle, this method will return that
share object.

 my $share = $easy->share;

Use setopt() with CURLOPT_SHARE option to attach the share object.

=item form( )

If form object is attached to this easy handle, this method will return that
form object.

 my $form = $easy->form;

Use setopt() with CURLOPT_HTTPPOST option to attach the share object.

=item escape( )

URL encodes the given string.

 my $escaped = $easy->escape( "+foo" );

Calls L<curl_easy_escape(3)|https://curl.haxx.se/libcurl/c/curl_easy_escape.html> which URL encode the given string.

=item unescape( )

URL decodes the given string.

 my $unescaped = $easy->unescape( "%2Bbar" );

Calls L<curl_easy_unescape(3)|https://curl.haxx.se/libcurl/c/curl_easy_unescape.html> which URL decodes the given string.

If you are sure the unescaped data contains a utf8 string, you can mark it
with utf8::decode( $unescaped )

=back

=head2 FUNCTIONS

None of those functions are exported, you must use fully qualified names.

=over

=item strerror( [WHATEVER], CODE )

Return a string for error code CODE.

 my $message = Net::Curl::Easy::strerror(
     Net::Curl::Easy::CURLE_OK
 );

Calls L<curl_easy_strerror(3)|https://curl.haxx.se/libcurl/c/curl_easy_strerror.html>.

=back

=head2 CONSTANTS

Net::Curl::Easy contains all the constants that do not form part of any
other Net::Curl modules. List below describes only the ones that behave
differently than their C counterparts.

=over

=item CURLOPT_PRIVATE

setopt() does not allow to use this constant. Hide any private data in your
base object.

=item CURLOPT_ERRORBUFFER

setopt() does not allow to use this constant. You can always retrieve latest
error message with $easy->error() method.

=back

=head2 CALLBACKS

Reffer to libcurl documentation for more detailed info on each of those.
Callbacks can be set using setopt() method.

 $easy->setopt( CURLOPT_somethingFUNCTION, \&callback_function );
 # or
 $easy->setopt( CURLOPT_somethingFUNCTION, "callback_method" );
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
and CURLOPT_SOCKOPTDATA value. Is should return one of CURL_SOCKOPT_*
values.

 sub cb_sockopt {
     my ( $easy, $socket, $purpose, $uservar ) = @_;
     # ... do something with the socket ...
     return CURL_SOCKOPT_OK;
 }

=item CURLOPT_OPENSOCKETFUNCTION ( CURLOPT_OPENSOCKETDATA ) 7.17.1+

opensocket callback receives 4 arguments: easy object, socket purpose,
address structure (in form of a hashref), and CURLOPT_OPENSOCKETDATA value.
The address structure has following numeric values: "family", "socktype",
"protocol"; and "addr" in binary form. Use Socket module to
decode "addr" field. You are also allowed to change those values.

Callback must return fileno of the socket or CURL_SOCKET_BAD on error.

 use Socket;
 sub cb_opensocket {
     my ( $easy, $purpose, $address, $uservar ) = @_;

     # decode addr information
     my ( $port, $ip ) = unpack_sockaddr_in( $address->{addr} );
     my $ip_string = inet_ntoa( $ip );

     # open the socket
     socket my $socket, $address->{family}, $address->{socktype},
         $address->{protocol};

     # save it somewhere so perl won't close the socket
     $opened_sockets{ fileno( $socket ) } = $socket;

     # return the socket
     return fileno $socket;
 }

=item CURLOPT_CLOSESOCKETFUNCTION ( CURLOPT_CLOSESOCKETDATA ) 7.21.7+

closesocket callback receives 3 arguments: easy object, socket fileno,
and CURLOPT_CLOSESOCKETDATA value.

 sub cb_closesocket {
     my ( $easy, $fileno, $uservar ) = @_;
     my $socket = delete $opened_sockets{ $fileno };
     close $socket;
 }

=item CURLOPT_PROGRESSFUNCTION ( CURLOPT_PROGRESSDATA )

Progress callback receives 6 arguments: easy object, dltotal, dlnow, ultotal,
ulnow and CURLOPT_PROGRESSDATA value. It should return 0.

 sub cb_progress {
     my ( $easy, $dltotal, $dlnow, $ultotal, $ulnow, $uservar ) = @_;
     # ... display progress ...
     return 0;
 }

Since CURLOPT_XFERINFODATA is an alias to CURLOPT_PROGRESSDATA,
they both set the same callback data for both
CURLOPT_PROGRESSFUNCTION and CURLOPT_PROGRESSFUNCTION callbacks.

=item CURLOPT_XFERINFOFUNCTION ( CURLOPT_XFERINFODATA ) 7.32.0+

Works exactly like CURLOPT_PROGRESSFUNCTION callback, except that dltotal, dlnow, ultotal
and ulnow are now integer values instead of double.

Since CURLOPT_XFERINFODATA is an alias to CURLOPT_PROGRESSDATA,
they both set the same callback data for both
CURLOPT_PROGRESSFUNCTION and CURLOPT_PROGRESSFUNCTION callbacks.

=item CURLOPT_HEADERFUNCTION ( CURLOPT_WRITEHEADER )

Behaviour is the same as in write callback. Callback is called once for
every header line.

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

=item CURLOPT_SSH_KEYFUNCTION ( CURLOPT_SSH_KEYDATA ) 7.19.6+

sshkey callback receives 4 arguments: easy object, known key, found key,
khmatch status and CURLOPT_SSH_KEYDATA value.
Must return one of CURLKHSTAT_* values.

 sub cb_sshkey {
     my ( $easy, $knownkey, $foundkey, $khmatch, $uservar ) = @_;
     return CURLKHSTAT_FINE_ADD_TO_FILE;
 }

=back

=head2 Net::Curl::Easy::Code

Most Net::Curl::Easy methods on failure throw a Net::Curl::Easy::Code error
object. It has both numeric value and, when used as string, it calls strerror()
function to display a nice message.

 eval {
     $easy->somemethod();
 };
 if ( ref $@ eq "Net::Curl::Easy::Code" ) {
     if ( $@ == CURLE_SOME_ERROR_WE_EXPECTED ) {
         warn "Expected error, continuing\n";
     } else {
         die "Unexpected curl error: $@\n";
     }
 } else {
     # rethrow everyting else
     die $@;
 }

=head1 SEE ALSO

L<Net::Curl>
L<Net::Curl::Multi>
L<Net::Curl::examples>
L<libcurl-easy(3)>
L<libcurl-errors(3)>

=head1 COPYRIGHT

Copyright (c) 2011-2015 Przemyslaw Iskra <sparky at pld-linux.org>.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.

=cut
