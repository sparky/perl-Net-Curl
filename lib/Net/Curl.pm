package Net::Curl;

use strict;
use warnings;
use Exporter 'import';

## no critic (ProhibitExplicitISA)
our @ISA;
our $VERSION;
BEGIN {
	$VERSION = '0.50';

	my $loaded = 0;

	my $load_xs = sub {
		require XSLoader;
		XSLoader::load( __PACKAGE__, $VERSION );
		$loaded = 1;
	};
	my $load_dyna = sub {
		require DynaLoader;
		@ISA = qw(DynaLoader);
		DynaLoader::bootstrap( __PACKAGE__ );
		$loaded = 1;
	};
	## no critic (RequireCheckingReturnValueOfEval)
	eval { $load_xs->() } if $INC{ "XSLoader.pm" };
	eval { $load_dyna->() } if $INC{ "DynaLoader.pm" } and not $loaded;
	unless ( $loaded ) {
		eval { $load_xs->(); };
		$load_dyna->() if $@;
	}
}

our @EXPORT_OK = grep { /^(?:LIB)?CURL/x } keys %{Net::Curl::};
our %EXPORT_TAGS = ( constants => \@EXPORT_OK );

1;

__END__

=head1 NAME

Net::Curl - Perl interface for libcurl

=head1 SYNOPSIS

 use Net::Curl;
 print $Net::Curl::VERSION;

 print Net::Curl::version();

=head1 DOCUMENTATION

Net::Curl provides a Perl interface to libcurl created with object-oriented
implementations in mind. This documentation contains Perl-specific details
and quirks. For more information consult libcurl man pages and documentation
at L<http://curl.haxx.se>.

=head1 DESCRIPTION

This package contains some static functions and version-releated constants.
It does not export by default anything, but constants can be exported upon
request.

 use Net::Curl qw(:constants);

To perform any request you want L<Net::Curl::Easy>.

=head2 FUNCTIONS

None of those functions are exported, you must use fully qualified names.

=over

=item version

Returns libcurl version string.

 my $libcurl_verstr = Net::Curl::version();
 # prints something like:
 # libcurl/7.21.4 GnuTLS/2.10.4 zlib/1.2.5 c-ares/1.7.4 ...
 print $libcurl_verstr;

Calls L<curl_version(3)|https://curl.haxx.se/libcurl/c/curl_version.html> function.

=item version_info

Returns a hashref with the same information as L<curl_version_info(3)|https://curl.haxx.se/libcurl/c/curl_version_info.html>.

 my $libcurl_ver = Net::Curl::version_info();
 print Dumper( $libcurl_ver );

Example for version_info with age CURLVERSION_FOURTH:

 age => 3,
 version => '7.21.4',
 version_num => 464132,
 host => 'x86_64-pld-linux-gnu',
 features => 18109,
 ssl_version => 'GnuTLS/2.10.4'
 ssl_version_num => 0,
 libz_version => '1.2.5',
 protocols => [ 'dict', 'file', 'ftp', 'ftps', 'gopher', 'http',
                'https', 'imap', 'imaps', 'ldap', 'ldaps', 'pop3',
                'pop3s', 'rtmp', 'rtsp', 'scp', 'sftp', 'smtp',
                'smtps', 'telnet', 'tftp' ],
 ares => '1.7.4',
 ares_num => 67332,
 libidn => '1.20',
 iconv_ver_num => 0,
 libssh_version => 'libssh2/1.2.7',

You can import constants if you want to check libcurl features:

 use Net::Curl qw(:constants);
 my $vi = Net::Curl::version_info();
 unless ( $vi->{features} & CURL_VERSION_SSL ) {
     die "SSL support is required\n";
 }

=item getdate

Decodes date string returning its numerical value, in seconds.

 my $time = Net::Curl::getdate( "GMT 08:49:37 06-Nov-94 Sunday" );
 my $timestr = gmtime $time;
 print "$timestr\n";
 # Sun Nov  6 08:49:37 1994

See L<curl_getdate(3)|https://curl.haxx.se/libcurl/c/curl_getdate.html> for more info on supported input formats.

=back

=head2 CONSTANTS

=over

=item CURL_VERSION_* and CURLVERSION_*

Can be used for decoding version_info() values. L<curl_version_info(3)|https://curl.haxx.se/libcurl/c/curl_version_info.html>

=item LIBCURL_*

Can be used for determining buildtime libcurl version. Some Net::Curl
features will not be available if it was built with older libcurl, even if
runtime libcurl version has necessary features.

=back

=head1 STATUS

Implemented interface is solid, there should be no more changes to it. Only
new features will be added.

This package tries very hard to not allow user do anything that could make
libcurl crash, but there still may be some corner cases where that happens.

=head1 AUTHORS

This package was mostly rewritten by Przemyslaw Iskra <sparky at pld-linux.org>.

=head1 HISTORY

Module started as an extension to L<WWW::Curl> developed by Cris Bailiff
<c.bailiff+curl at devsecure.com>, Balint Szilakszi <szbalint at cpan.org>
and a long list of contributors. However, currently it shares no common code.

=head1 COPYRIGHT

Copyright (c) 2011-2015 Przemyslaw Iskra.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.

=head1 SEE ALSO

L<Net::Curl::Easy>
L<Net::Curl::Compat>
L<Net::Curl::examples>
L<http://curl.haxx.se>
L<libcurl(3)>

=cut
