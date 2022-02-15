package Net::Curl::Multi;
use strict;
use warnings;

use Net::Curl ();
use Exporter 'import';

our $VERSION = '0.50';

our @EXPORT_OK = grep { /^CURL/x } keys %{Net::Curl::Multi::};
our %EXPORT_TAGS = ( constants => \@EXPORT_OK );

## no critic (ProhibitMultiplePackages)
package Net::Curl::Multi::Code;

use overload
	'0+' => sub {
		return ${(shift)};
	},
	'""' => sub {
		return Net::Curl::Multi::strerror( ${(shift)} );
	},
	fallback => 1;

1;

__END__

=head1 NAME

Net::Curl::Multi - Perl interface for curl_multi_* functions

=head1 SYNOPSIS

 use Net::Curl::Multi qw(:constants);

 my $multi = Net::Curl::Multi->new();
 $multi->add_handle( $easy );

 my $running = 0;
 do {
     my ($r, $w, $e) = $multi->fdset();
     my $timeout = $multi->timeout();
     select $r, $w, $e, $timeout / 1000
         if $timeout > 0;

     $running = $multi->perform();
     while ( my ( $msg, $easy, $result ) = $multi->info_read() ) {
         $multi->remove_handle( $easy );

         # process $easy
     }
 } while ( $running );

=head1 DESCRIPTION

This module wraps multi handle from libcurl and all related functions and
constants. It does not export by default anything, but constants can be
exported upon request.

 use Net::Curl::Multi qw(:constants);

=head2 CONSTRUCTOR

=over

=item new( [BASE] )

Creates new Net::Curl::Multi object. If BASE is specified it will be used
as object base, otherwise an empty hash will be used. BASE must be a valid
reference which has not been blessed already. It will not be used by the
object.

 my $multi = Net::Curl::Multi->new( [qw(my very private data)] );

Calls L<curl_multi_init(3)|https://curl.haxx.se/libcurl/c/curl_multi_init.html> and presets some defaults.

=back

=head2 METHODS

=over

=item add_handle( EASY )

Add Net::Curl::Easy to this Net::Curl::Multi object.

 $multi->add_handle( $easy );

Calls L<curl_multi_add_handle(3)|https://curl.haxx.se/libcurl/c/curl_multi_add_handle.html>.
Throws L</Net::Curl::Multi::Code> on error.

=item remove_handle( EASY )

Remove Net::Curl::Easy from this Net::Curl::Multi object.

 $multi->remove_handle( $easy );

Calls L<curl_multi_remove_handle(3)|https://curl.haxx.se/libcurl/c/curl_multi_remove_handle.html>.
Rethrows exceptions from callbacks.
Throws L</Net::Curl::Multi::Code> on error.

=item info_read( )

Read last message from this Multi.

 my ( $msg, $easy, $result ) = $multi->info_read();

$msg contains one of CURLMSG_* values, currently only CURLMSG_DONE is returned.
$easy is the L<Net::Curl::Easy> object. Result is a
L<Net::Curl::Easy::Code> dualvar object.

Calls L<curl_multi_info_read(3)|https://curl.haxx.se/libcurl/c/curl_multi_info_read.html>.

=item fdset( )

Returns read, write and exception vectors suitable for
L<select()|perlfunc/select> and L<vec()|perlfunc/vec> perl builtins.

 my ( $rvec, $wvec, $evec ) = $multi->fdset();

Calls L<curl_multi_fdset(3)|https://curl.haxx.se/libcurl/c/curl_multi_fdset.html>.
Throws L</Net::Curl::Multi::Code> on error.

=item timeout( )

Returns timeout value in miliseconds.

 my $timeout_ms = $multi->timeout();

Calls L<curl_multi_timeout(3)|https://curl.haxx.se/libcurl/c/curl_multi_timeout.html>.
Throws L</Net::Curl::Multi::Code> on error.

=item setopt( OPTION, VALUE )

Set an option. OPTION is a numeric value, use one of CURLMOPT_* constants.
VALUE depends on whatever that option expects.

 $multi->setopt( CURLMOPT_MAXCONNECTS, 10 );

Calls L<curl_multi_setopt(3)|https://curl.haxx.se/libcurl/c/curl_multi_setopt.html>.
Throws L</Net::Curl::Multi::Code> on error.

=item perform( )

Perform. Call it if there is some activity on any fd used by multi interface
or timeout has just reached zero.

 my $active = $multi->perform();

Calls L<curl_multi_perform(3)|https://curl.haxx.se/libcurl/c/curl_multi_perform.html>.
Rethrows exceptions from callbacks.
Throws L</Net::Curl::Multi::Code> on error.

=item wait( [OTHER_FDS], TIMEOUT_MS )

This method polls on all file descriptors used by the curl easy handles contained in the given multi handle set.
It will block until activity is detected on at least one of the handles or TIMEOUT_MS has passed.

 my $active = $multi->wait(1000);

It will also poll on all filehandles requested. Each event descriptor is a hash and requires keys: fd - file number of the handle and events - a bitmask of the events to wait for. On detected event it will return the data in revents key.

 my $ev_read_stdin = {
   fd => fileno STDIN,
   events => CURL_WAIT_POLLIN,
 };

 my $active = $multi->wait( [ $ev_read_stdin ], 1000 );
 if ( $active and $ev_read_stdin->{revents} == CURL_WAIT_POLLIN )
 {
   # STDIN is ready to read
   ...
 }

Calls L<curl_multi_wait(3)|https://curl.haxx.se/libcurl/c/curl_multi_wait.html>
(L<available since libcurl/7.28.0|http://curl.haxx.se/libcurl/c/curl_multi_wait.html>).
Rethrows exceptions from callbacks.
Throws L</Net::Curl::Multi::Code> on error.

=item socket_action( [SOCKET], [BITMASK] )

Signalize action on a socket.

 my $active = $multi->socket_action();

 # there is data to read on socket:
 my $active = $multi->socket_action( $socket, CURL_CSELECT_IN );

Calls L<curl_multi_socket_action(3)|https://curl.haxx.se/libcurl/c/curl_multi_socket_action.html>.
Rethrows exceptions from callbacks.
Throws L</Net::Curl::Multi::Code> on error.

=item assign( SOCKET, [VALUE] )

Assigns some value to a socket file descriptor. Removes it if value is not
specified. The value is used only in socket callback.

 my $socket = some_socket_open(...);

 # store socket object for socket callback
 $multi->assign( $socket->fileno(), $socket );

Calls L<curl_multi_assign(3)|https://curl.haxx.se/libcurl/c/curl_multi_assign.html>.
Throws L</Net::Curl::Multi::Code> on error.

=item handles( )

In list context returns easy handles attached to this multi.
In scalar context returns number of easy handles attached.

There is no libcurl equivalent.

=back

=head2 FUNCTIONS

None of those functions are exported, you must use fully qualified names.

=over

=item strerror( [WHATEVER], CODE )

Return a string for error code CODE.

 my $message = $multi->strerror( CURLM_BAD_EASY_HANDLE );

See L<curl_multi_strerror(3)|https://curl.haxx.se/libcurl/c/curl_multi_strerror.html> for more info.

=back

=head2 CONSTANTS

=over

=item CURLM_*

If any method fails, it will return one of those values.

=item CURLMSG_*

Message type from info_read().

=item CURLMOPT_*

Option values for setopt().

=item CURL_POLL_*

Poll action information for socket callback.

=item CURL_CSELECT_*

Select bits for socket_action() method.

=item CURL_SOCKET_TIMEOUT

Special socket value for socket_action() method.

=back

=head2 CALLBACKS

=over

=item CURLMOPT_SOCKETFUNCTION ( CURLMOPT_SOCKETDATA )

Socket callback will be called only if socket_action() method is being used.
It receives 6 arguments: multi handle, easy handle, socket file number, poll
action, socket data (see assign), and CURLMOPT_SOCKETDATA value. It must
return 0.
For more information refer to L<curl_multi_socket_action(3)|https://curl.haxx.se/libcurl/c/curl_multi_socket_action.html>.

 sub cb_socket {
     my ( $multi, $easy, $socketfn, $action, $socketdata, $uservar ) = @_;
     # ... register or deregister socket actions ...
     return 0;
 }

=item CURLMOPT_TIMERFUNCTION ( CURLMOPT_TIMERDATA ) 7.16.0+

Timer callback receives 3 arguments: multi object, timeout in ms, and
CURLMOPT_TIMERDATA value. Should return 0.

 sub cb_timer {
     my ( $multi, $timeout_ms, $uservar ) = @_;
     # ... update timeout ...
     return 0;
 }

=back

=head2 Net::Curl::Multi::Code

Most Net::Curl::Multi methods on failure throw a Net::Curl::Multi::Code error
object. It has both numeric value and, when used as string, it calls strerror()
function to display a nice message.

 eval {
     $multi->somemethod();
 };
 if ( ref $@ eq "Net::Curl::Easy::Code" ) {
     if ( $@ == CURLM_SOME_ERROR_WE_EXPECTED ) {
         warn "Expected multi error, continuing\n";
     } else {
         die "Unexpected curl multi error: $@\n";
     }
 } else {
     # rethrow everyting else
     die $@;
 }


=head1 SEE ALSO

L<Net::Curl>
L<Net::Curl::Easy>
L<Net::Curl::examples>
L<libcurl-multi(3)>
L<libcurl-errors(3)>

=head1 COPYRIGHT

Copyright (c) 2011-2015 Przemyslaw Iskra <sparky at pld-linux.org>.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.

=cut
