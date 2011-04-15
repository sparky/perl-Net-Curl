package WWW::CurlOO::Share;
use strict;
use warnings;

use WWW::CurlOO ();
use Exporter 'import';

*VERSION = \*WWW::CurlOO::VERSION;

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

=head1 SYNOPSIS

 use WWW::CurlOO::Share qw(:constants);

 my $share = WWW::CurlOO::Share->new();
 $share->setopt( CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE );
 $share->setopt( CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS );

 $easy_one->setopt( CURLOPT_SHARE() => $share );

 $easy_two->setopt( CURLOPT_SHARE() => $share );

=head1 DESCRIPTION

This module wraps share handle from libcurl and all related functions and
constants. It does not export by default anything, but constants can be
exported upon request.

 use WWW::CurlOO::Share qw(:constants);

=head2 CONSTRUCTOR

=over

=item new( [BASE] )

Creates new WWW::CurlOO::Share object. If BASE is specified it will be used
as object base, otherwise an empty hash will be used. BASE must be a valid
reference which has not been blessed already. It will not be used by the
object.

 my $share = WWW::CurlOO::Share->new( [qw(my very private data)] );

Calls L<curl_share_init(3)>.

=back

=head2 METHODS

=over

=item setopt( OPTION, VALUE )

Set an option. OPTION is a numeric value, use one of CURLSHOPT_* constants.
VALUE depends on whatever that option expects.

 $share->setopt( CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE );

Calls L<curl_share_setopt(3)>.
Throws L</WWW::CurlOO::Share::Code> on error.

=back

=head2 FUNCTIONS

None of those functions are exported, you must use fully qualified names.

=over

=item strerror( [WHATEVER], CODE )

Return a string for error code CODE.

 my $message = WWW::CurlOO::Share::strerror( CURLSHE_BAD_OPTION );

See L<curl_share_strerror(3)> for more info.

=back

=head2 CONSTANTS

=over

=item CURLSHOPT_*

Values for setopt().

=item CURL_LOCK_ACCESS_*

Values passed to lock callbacks.

=item CURL_LOCK_DATA_*

Values passed to lock and unlock callbacks.

=back

=head2 CALLBACKS

Reffer to libcurl documentation for more detailed info on each of those.

=over

=item CURLSHOPT_LOCKFUNC ( CURLSHOPT_USERDATA )

Lock callback receives 5 arguments: share object, easy object, lock data,
lock access, and CURLSHOPT_USERDATA value. Easy may be undefined in some cases.

 sub cb_lock {
     my ( $share, $easy, $data, $locktype, $uservar ) = @_;
     # ... lock ...
 }

=item CURLSHOPT_UNLOCKFUNC ( CURLSHOPT_USERDATA )

Unlock callback receives 4 arguments: share object, easy object, lock data, and
CURLSHOPT_USERDATA value. Easy may be undefined in some cases.

 sub cb_unlock {
     my ( $share, $easy, $data, $uservar ) = @_;
     # ... unlock ...
 }

=back

=head2 WWW::CurlOO::Share::Code

WWW::CurlOO::Share setopt method on failure throws a WWW::CurlOO::Share::Code error
object. It has both numeric value and, when used as string, it calls strerror()
function to display a nice message.

=head1 SEE ALSO

L<WWW::CurlOO>
L<WWW::CurlOO::Easy>
L<WWW::CurlOO::Multi>
L<WWW::CurlOO::examples>
L<libcurl-share(3)>
L<libcurl-errors(3)>

=head1 COPYRIGHT

Copyright (c) 2011 Przemyslaw Iskra <sparky at pld-linux.org>.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.
