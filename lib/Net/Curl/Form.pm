package Net::Curl::Form;
use strict;
use warnings;

use Net::Curl ();
use Exporter 'import';

our $VERSION = '0.50';

our @EXPORT_OK = grep { /^CURL/x } keys %{Net::Curl::Form::};
our %EXPORT_TAGS = ( constants => \@EXPORT_OK );

sub strerror
{
	# first arg may be an object, package, or nothing
	my (undef, $code) = @_;

	foreach my $c ( grep { /^CURL_FORMADD_/x } keys %{Net::Curl::Form::} ) {
		next unless Net::Curl::Form->$c() == $code;
		local $_ = $c;
		s/^CURL_FORMADD_//x;
		tr/_/ /;
		return ucfirst lc $_;
	}
	return "Invalid formadd error code";
}

## no critic (ProhibitMultiplePackages)
package Net::Curl::Form::Code;

use overload
	'0+' => sub {
		return ${(shift)};
	},
	'""' => sub {
		return Net::Curl::Form::strerror( ${(shift)} );
	},
	fallback => 1;

1;

__END__

=head1 NAME

Net::Curl::Form - Form builder for Net::Curl

=head1 SYNOPSIS

 use Net::Curl::Form qw(:constants);

 my $form = Net::Curl::Form->new();
 $form->add(
     CURLFORM_COPYNAME() => $name,
     CURLFORM_COPYCONTENTS() => $data
 );
 $form->add(
     CURLFORM_COPYNAME() => $filename,
     CURLFORM_FILE() => $filename
 );


 # most likely use:
 $easy->setopt( CURLOPT_HTTPPOST() => $form );

 # serialize
 my $serial = $form->get();

=head1 DESCRIPTION

This module lets you build multipart/form-data HTTP POST. When finished it can
be either supplied to Net::Curl::Easy handle or serialized manually.
Net::Curl::Form does not export by default anything, but constants can be
exported upon request.

 use Net::Curl::Form qw(:constants);

=head2 CONSTRUCTOR

=over

=item new( [BASE] )

Creates new Net::Curl::Form object. If BASE is specified it will be used
as object base, otherwise an empty hash will be used. BASE must be a valid
reference which has not been blessed already. It will not be used by the
object.

 my $form = Net::Curl::Form->new( [qw(my very private data)] );

=back

=head2 METHODS

=over

=item add( CURLFORM_option => DATA, ... )

Adds new section to form object. See L<curl_formadd(3)|https://curl.haxx.se/libcurl/c/curl_formadd.html> for more info.

Unlike in libcurl function, there is no need to add CURLFORM_END as the last
argument.

On error this method dies with L</Net::Curl::Form::Code> error object.

Buffer and name options automatibally set their length values
so there is no need to set length even if there is a NUL
character in the data. If you want to shorten the buffer CURLFORM_*LENGTH
options must be set inmediatelly after their buffer option, otherwise
an CURL_FORMADD_OPTION_TWICE exception will occur.

 $form->add(
     CURLFORM_COPYNAME() => "name",
     CURLFORM_COPYCONTENTS() => "content\0binary"
 );
 $form->add(
     CURLFORM_PTRNAME() => "name",
     CURLFORM_NAMELENGTH() => 2,
     CURLFORM_PTRCONTENTS() => "content",
     CURLFORM_CONTENTSLENGTH() => 4,
 );
 $form->add(
     CURLFORM_COPYNAME, "htmlcode",
     CURLFORM_COPYCONTENTS, "<HTML></HTML>",
     CURLFORM_CONTENTTYPE, "text/html"
 );
 $form->add(
     CURLFORM_COPYNAME, "picture",
     CURLFORM_FILE, "my-face.jpg"
 );
 $form->add(
     CURLFORM_COPYNAME, "picture",
     CURLFORM_FILE, "my-face.jpg",
     CURLFORM_CONTENTTYPE, "image/jpeg"
 );
 $form->add(
     CURLFORM_COPYNAME, "picture",
     CURLFORM_FILE, "my-face.jpg",
     CURLFORM_FILE, "your-face.jpg",
 );
 $form->add(
     CURLFORM_COPYNAME, "filecontent",
     CURLFORM_FILECONTENT, ".bashrc"
 );


=item get( [BUFFER / FH / USERDATA], [CALLBACK] )

Use it to serialize the form object. Normally there is no need to use it
because Net::Curl::Easy will serialize it while uploading data.

There are multiple ways to perform serialization:

=over

=item direct

With no arguments a scalar is returned.

 my $serial = $form->get();

=item write to file handle

If there is only one argument and it is a GLOB or a GLOB reference,
serialized contents will be written to that file handle.

 open my $file, ">", "post.txt";
 $form->get( $file );

=item write to buffer

If there is only one argument and it is writable, serialized contents
will be concatenated to it.

 my $serial;
 $form->get( $serial );

 # same as above
 $form->get( \$serial );

=item use a callback

With two arguments, second one must be a function that will be called for
serialization. First argument is a user data that will be passed to that
function.

The callback will receive three arguments: form object, data buffer and
user data. It must return the length of the data buffer, otherwise
serialization will be aborted.

 sub cb_serial
 {
     my ( $form, $data, $uservar ) = @_;

     # do anything you want

     return length $data;
 }
 $form->get( "userdata", \&cb_serial );

=back

Calls L<curl_formget(3)|https://curl.haxx.se/libcurl/c/curl_formget.html>. Rethrows exceptions from callbacks.

=back

=head2 FUNCTIONS

None of those functions are exported, you must use fully qualified names.

=over

=item strerror( [WHATEVER], CODE )

Return a string for error code CODE.
String is extracted from error constant name.

 my $message = Net::Curl::Form->strerror(
     Net::Curl::Form::CURL_FORMADD_OPTION_TWICE
 );

=back

=head2 CONSTANTS

=over

=item CURLFORM_*

Most of those constants can be used in add() method. Currently CURLFORM_STREAM
and CURLFORM_ARRAY are not supported. Others will behave in the way described
in L<curl_formadd(3)|https://curl.haxx.se/libcurl/c/curl_formadd.html>.

=item CURL_FORMADD_*

If add() fails it will return one of those values.

=back

=head2 CALLBACKS

Callback for get() is described already in L</"use a callback"> subsection.

=head2 Net::Curl::Form::Code

Net::Curl::Form add() method on failure throws a Net::Curl::Form::Code error
object. It has both numeric value and, when used as string, it calls strerror()
function to display a nice message.

=head1 SEE ALSO

L<Net::Curl>
L<Net::Curl::Easy>
L<curl_formadd(3)|https://curl.haxx.se/libcurl/c/curl_formadd.html>

=head1 COPYRIGHT

Copyright (c) 2011-2015 Przemyslaw Iskra <sparky at pld-linux.org>.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.

=cut
