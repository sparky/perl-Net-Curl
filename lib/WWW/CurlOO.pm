package WWW::CurlOO;

use strict;
use warnings;
use XSLoader;
use Exporter ();

our $VERSION;
BEGIN {
	$VERSION = '0.01';
	XSLoader::load(__PACKAGE__, $VERSION);
}
END {
    _global_cleanup();
}

our @ISA = qw(Exporter);
our @EXPORT_OK = (
# @CURLOPT_INCLUDE@
);

our %EXPORT_TAGS = ( constants => \@EXPORT_OK );

1;

__END__

=head1 NAME

WWW::CurlOO - Perl interface for libcurl

=head1 WARNING

THIS MODULE IS UNDER HEAVY DEVELOPEMENT AND SOME INTERFACE MAY CHANGE YET.

=head1 SYNOPSIS

    use WWW::CurlOO;
    print $WWW::CurlOO::VERSION;


=head1 DESCRIPTION

WWW::CurlOO is a Perl interface for libcurl.

=head1 DOCUMENTATION

This module provides a Perl interface to libcurl. It is not intended to be a standalone module
and because of this, the main libcurl documentation should be consulted for API details at
L<http://curl.haxx.se>. The documentation you're reading right now only contains the Perl specific
details, some sample code and the differences between the C API and the Perl one.

=head1 WWW::CurlOO

This package contains some static functions and version-releated constants.
It does not export by default anything, but constants can be exported upon
request.

	use WWW::CurlOO qw(:constants);

=head2 FUNCTIONS

=over

=item version

Returns libcurl version string. See L<curl_version(3)> for more info.

	my $libcurl_verstr = WWW::CurlOO::version();
	# prints something like:
	# libcurl/7.21.4 GnuTLS/2.10.4 zlib/1.2.5 c-ares/1.7.4 libidn/1.20 libssh2/1.2.7 librtmp/2.3
	print $libcurl_verstr;

=item version_info

Returns a hashref with the same information as L<curl_version_info(3)>.
	
	my $libcurl_ver = WWW::CurlOO::version_info();

	print Dumper( $libcurl_ver );

Example for version_info with age CURLVERSION_FOURTH:

	'age' => 3,
	'version' => '7.21.4',
	'version_num' => 464132,
	'host' => 'x86_64-pld-linux-gnu',
	'features' => 18109,
	'ssl_version' => 'GnuTLS/2.10.4'
	'ssl_version_num' => 0,
	'libz_version' => '1.2.5',
	'protocols' => [ 'dict', 'file', 'ftp', 'ftps', 'gopher', 'http', 'https',
		'imap', 'imaps', 'ldap', 'ldaps', 'pop3', 'pop3s', 'rtmp', 'rtsp',
		'scp', 'sftp', 'smtp', 'smtps', 'telnet', 'tftp' ],
	'ares' => '1.7.4',
	'ares_num' => 67332,
	'libidn' => '1.20',
	'iconv_ver_num' => 0,
	'libssh_version' => 'libssh2/1.2.7',
	
You can import constants if you want to check libcurl features:

	use WWW::CurlOO qw(:constants);
	unless ( WWW::CurlOO::version_info()->{features} & CURL_VERSION_SSL ) {
		die "SSL support is required
	}

=item getdate

Decodes date string returning its numerical value, in seconds.

	my $time = WWW::CurlOO::getdate( "GMT 08:49:37 06-Nov-94 Sunday" );
	my $timestr = gmtime $time;
	print "$timestr\n";
	# Sun Nov  6 08:49:37 1994

See L<curl_getdate(3)> for more info on supported input formats.

=item constant

Unused.

=back

=head1 AUTHORS

This package was mostly rewritten by Przemyslaw Iskra <sparky at pld-linux.org>.

It is based on WWW::Curl developed by Cris Bailiff <c.bailiff+curl at devsecure.com>
and Balint Szilakszi <szbalint at cpan.org>.

Original Author Georg Horn <horn@koblenz-net.de>, with additional callback,
pod and test work by Cris Bailiff <c.bailiff+curl@devsecure.com> and
Forrest Cahoon <forrest.cahoon@merrillcorp.com>. Sebastian Riedel added ::Multi
and Anton Fedorov (datacompboy <at> mail.ru) added ::Share. Balint Szilakszi
repackaged the module into a more modern form.

=head1 COPYRIGHT

Copyright (c) 2011 Przemyslaw Iskra.

Copyright (C) 2000-2005,2008-2010 Daniel Stenberg, Cris Bailiff,
Sebastian Riedel, Balint Szilakszi et al.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.

=head1 SEE ALSO

L<http://curl.haxx.se>

L<libcurl(3)>
