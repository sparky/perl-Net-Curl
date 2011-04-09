=head1 Multi::Simple

This module shows how to use WWW::CurlOO::Multi interface correctly in its
simpliest form. Uses perl builtin select(). A more advanced code would use
callbacks and some event library instead.

=head2 Motivation

Writing a proper multi wrapper code requires a rather good understainding
of libcurl multi interface. This code provides a recipie for those who just
need something that "simply works".

=head2 MODULE CODE

=cut
package Multi::Simple;

use strict;
use warnings;
use WWW::CurlOO::Multi;
use base qw(WWW::CurlOO::Multi);

# make new object, preset the data
sub new
{
	my $class = shift;
	my $active = 0;
	return $class->SUPER::new( \$active );
}

# add one handle and count it
sub add_handle($$)
{
	my $self = shift;
	my $easy = shift;

	$$self++;
	$self->SUPER::add_handle( $easy );
}

# perform until some handle finishes, does all the magic needed to make it
# efficient (check as soon as there is some data) without overusing the cpu.
sub get_one($)
{
	my $self = shift;

	if ( my @result = $self->info_read() ) {
		$self->remove_handle( $result[ 1 ] );
		return @result;
	}

	while ( $$self ) {
		my $t = $self->timeout;
		if ( $t != 0 ) {
			$t = 10000 if $t < 0;
			my ( $r, $w, $e ) = $self->fdset;

			select $r, $w, $e, $t / 1000;
		}

		my $ret = $self->perform();
		if ( $$self != $ret ) {
			$$self = $ret;
			if ( my @result = $self->info_read() ) {
				$self->remove_handle( $result[ 1 ] );
				return @result;
			}
		}
	};

	return ();
}

1;

=head2 TEST APPLICATION

Sample application using this module looks like this:

	#!perl
	use strict;
	use warnings;
	use Multi::Simple;
#nopod
=cut
package main;
use strict;
use warnings;
#endnopod
use WWW::CurlOO::Share qw(:constants);


sub easy
{
	my $uri = shift;
	my $share = shift;

	require WWW::CurlOO::Easy;

	my $easy = WWW::CurlOO::Easy->new( { uri => $uri, body => '' } );
	$easy->setopt( WWW::CurlOO::Easy::CURLOPT_VERBOSE(), 1 );
	$easy->setopt( WWW::CurlOO::Easy::CURLOPT_URL(), $uri );
	$easy->setopt( WWW::CurlOO::Easy::CURLOPT_WRITEHEADER(), \$easy->{headers} );
	$easy->setopt( WWW::CurlOO::Easy::CURLOPT_FILE(), \$easy->{body} );
	$easy->setopt( WWW::CurlOO::Easy::CURLOPT_SHARE(), $share );
	return $easy;
}

my $multi = Multi::Simple->new();

my @uri = (
	"http://www.google.com/search?q=perl",
	"http://www.google.com/search?q=curl",
	"http://www.google.com/search?q=perl+curl",
);

{
	# share cookies between all handles
	my $share = WWW::CurlOO::Share->new();
	$share->setopt( CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE );
	$multi->add_handle( easy( shift ( @uri ), $share ) );
}

my $ret = 0;
while ( my ( $msg, $easy, $result ) = $multi->get_one() ) {
	print "\nFinished downloading $easy->{uri}: $result:\n";
	printf "Body is %d bytes long\n", length $easy->{body};
	print "=" x 80 . "\n";

	$ret = 1 if $result;

	$multi->add_handle( easy( shift ( @uri ), $easy->share ) ) if @uri;
}

exit $ret;
#nopod
# vim: ts=4:sw=4
