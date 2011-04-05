package WWW::CurlOO::Multi;
use strict;
use warnings;

use WWW::CurlOO ();
use Exporter ();

*VERSION = \*WWW::CurlOO::VERSION;

our @ISA = qw(Exporter);
our @EXPORT_OK = grep /^CURL/, keys %{WWW::CurlOO::Multi::};
our %EXPORT_TAGS = ( constants => \@EXPORT_OK );

package WWW::CurlOO::Multi::Code;

use overload
	'0+' => sub {
		return ${(shift)};
	},
	'""' => sub {
		return WWW::CurlOO::Multi::strerror( ${(shift)} );
	},
	fallback => 1;

1;

__END__

=head1 NAME

WWW::CurlOO::Multi - Perl interface for curl_multi_* functions

=head1 WARNING

B<THIS MODULE IS UNDER HEAVY DEVELOPEMENT AND SOME INTERFACE MAY CHANGE YET.>

=head1 SYNOPSIS

 use WWW::CurlOO::Multi qw(:constants);

 my $multi = WWW::CurlOO::Multi->new();
 $multi->add_handle( $easy );

 my $running = 0;
 do {
     my ($r, $w, $e) = $multi->fdset();
     my $timeout = $multi->timeout();
     select $r, $w, $e, $timeout / 1000
         if $timeout > 0;

     $running = $multi->perform();
     while ( my ( $easy, $result, $msg ) = $multi->info_read() ) {
         $multi->remove_handle( $easy );

         # process $easy
     }
 } while ( $running );

=head1 DESCRIPTION

This module wraps multi handle from libcurl and all related functions and
constants. It does not export by default anything, but constants can be
exported upon request.

 use WWW::CurlOO::Multi qw(:constants);

=head1 METHODS

=over

=item CLASS->new( [BASE] )

Creates new WWW::CurlOO::Multi object. If BASE is specified it will be used
as object base, otherwise an empty hash will be used. BASE must be a valid
reference which has not been blessed already. It will not be used by the
object.

Calls L<curl_multi_init(3)> and presets some defaults.

=item OBJECT->add_handle( EASY )

Add WWW::CurlOO::Easy to this WWW::CurlOO::Multi object.

Calls L<curl_multi_add_handle(3)>.

=item OBJECT->remove_handle( EASY )

Remove WWW::CurlOO::Easy from this WWW::CurlOO::Multi object.

Calls L<curl_multi_remove_handle(3)>.

=item OBJECT->info_read( )

Read last message from this Multi.

Calls L<curl_multi_info_read(3)>.

=item OBJECT->fdset( )

Returns read, write and exception vectors suitable for
L<select()|perlfunc/select> and L<vec()|perlfunc/vec> perl builtins.

Calls L<curl_multi_fdset(3)>.

=item OBJECT->timeout( )

Returns timeout value.

Calls L<curl_multi_timeout(3)>.

=item OBJECT->setopt( OPTION, VALUE )

Set an option. OPTION is a numeric value, use one of CURLMOPT_* constants.
VALUE depends on whatever that option expects.

Calls L<curl_multi_setopt(3)>.

=item OBJECT->perform( )

Perform.

Calls L<curl_multi_perform(3)>.

=item OBJECT->socket_action( [SOCKET], [BITMASK] )

Signalize action on a socket.

Calls L<curl_multi_socket_action(3)>.

=item OBJECT->DESTROY( )

Cleans up. It should not be called manually.

Calls L<curl_multi_cleanup(3)>.

=back

=head1 FUNCTIONS

=over

=item strerror( [WHATEVER], CODE )

Return a string for error code CODE.

See L<curl_multi_strerror(3)> for more info.

=back

=head1 SEE ALSO

L<WWW::CurlOO>
L<WWW::CurlOO::Easy>

=head1 COPYRIGHT

Copyright (c) 2011 Przemyslaw Iskra <sparky at pld-linux.org>.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.
