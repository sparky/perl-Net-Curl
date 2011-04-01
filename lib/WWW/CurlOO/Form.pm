package WWW::CurlOO::Form;
use strict;
use warnings;

use WWW::CurlOO ();
use Exporter ();

our @ISA = qw(Exporter);
our @EXPORT_OK = (
# @CURLOPT_INCLUDE@
);

our %EXPORT_TAGS = ( constants => \@EXPORT_OK );

1;

__END__

=head1 NAME

WWW::CurlOO::Form - Form builder for WWW::CurlOO

=head1 WARNING

THIS MODULE IS UNDER HEAVY DEVELOPEMENT AND SOME INTERFACE MAY CHANGE YET.

=head1 SYNOPSIS

 use WWW::CurlOO::Form qw(:constants);

 my $form = WWW::CurlOO::Form->new();
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
be either supplied to WWW::CurlOO::Easy handle or serialized manually.

=head1 METHODS

=over

=item CLASS->new( [BASE] )

Creates new WWW::CurlOO::Form object. If BASE is specified it will be used
as object base, otherwise an empty hash will be used. BASE must be a valid
reference which has not been blessed already. It will not be used by the
object.

=item OBJECT->add( CURLFORM_option => DATA, ... )

Adds new section to form object. See L<curl_formadd(3)> for more info.
B<WARNING: currently some option combination may crash your perl.>

Working options include: CURLFORM_COPYNAME, CURLFORM_NAMELENGTH,
CURLFORM_COPYCONTENTS, CURLFORM_CONTENTSLENGTH, CURLFORM_FILECONTENT,
CURLFORM_FILE, CURLFORM_CONTENTTYPE, CURLFORM_FILENAME.

Unlike in libcurl function, there is no need to add CURLFORM_END as the last
argument.

On error this method dies with message: "curl_formadd() failed: $CURLFORMcode\n",
where $CURLFORMcode is a decimal number.

Options CURLFORM_COPYNAME and CURLFORM_COPYCONTENTS automatibally set
appropriate their length values (CURLFORM_NAMELENGTH and CURLFORM_CONTENTSLENGTH
respectively) so there is no need to set length even if there is a NUL
character in the data. If you want to shorten the buffer CURLFORM_*LENGTH
options must be set inmediatelly after their CURLFORM_COPY* options, otherwise
an CURL_FORMADD_OPTION_TWICE exception will occur.

 $form->add(
     CURLFORM_COPYNAME() => "name",
     CURLFORM_COPYCONTENTS() => "content\0binary"
 );
 $form->add(
     CURLFORM_COPYNAME() => "name",
     CURLFORM_NAMELENGTH() => 2,
     CURLFORM_COPYCONTENTS() => "content",
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


=item OBJECT->get( [BUFFER / FH / USERDATA], [CALLBACK] )

Use it to serialize the form object. Normally there is no need to use it
because WWW::CurlOO::Easy will serialize it while uploading data.

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
     my ( $form, $data, $userdata ) = @_;

     # do anything you want

     return length $data;
 }
 $form->get( "userdata", \&cb_serial );

=back

See also L<curl_formget(3)>.

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
