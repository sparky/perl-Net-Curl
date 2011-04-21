=head1 Irssi async downloader

=cut

#package Irssi::Script::downloader;

use strict;
use Irssi ();
use WWW::CurlOO::Multi qw(/^CURL_POLL_/ /^CURL_CSELECT_/);
use base qw(WWW::CurlOO::Multi);

BEGIN {
	if ( not WWW::CurlOO::Multi->can( 'CURLMOPT_TIMERFUNCTION' ) ) {
		die "WWW::CurlOO::Multi is missing timer callback,\n" .
			"rebuild WWW::CurlOO with libcurl 7.16.0 or newer\n";
	}
}

sub new
{
	my $class = shift;

	my $multi = $class->SUPER::new();

	$multi->setopt( WWW::CurlOO::Multi::CURLMOPT_SOCKETFUNCTION,
		\&_cb_socket );
	$multi->setopt( WWW::CurlOO::Multi::CURLMOPT_TIMERFUNCTION,
		\&_cb_timer );

	$multi->{active} = -1;

	return $multi;
}


sub _cb_socket
{
	my ( $multi, $easy, $socket, $poll ) = @_;

	# deregister old io events
	if ( exists $multi->{ "io$socket" } ) {
		Irssi::input_remove( delete $multi->{ "io$socket" } );
	}

	my $cond = 0;
	my $action = 0;
	if ( $poll == CURL_POLL_IN ) {
		$cond = Irssi::INPUT_READ();
		$action = CURL_CSELECT_IN;
	} elsif ( $poll == CURL_POLL_OUT ) {
		$cond = Irssi::INPUT_WRITE();
		$action = CURL_CSELECT_OUT;
	} elsif ( $poll == CURL_POLL_INOUT ) {
		$cond = Irssi::INPUT_READ() | Irssi::INPUT_WRITE();
		# let libcurl figure it out
		$action = 0;
	} else {
		return 1;
	}

	$multi->{ "io$socket" } = Irssi::input_add( $socket, $cond,
		sub { $multi->socket_action( $socket, $action ); },
		'' );

	return 1;
}


sub _cb_timer
{
	my ( $multi, $timeout_ms ) = @_;

	# deregister old timer
	if ( exists $multi->{timer} ) {
		Irssi::timeout_remove( delete $multi->{timer} );
	}

	my $cb = sub {
		$multi->socket_action( WWW::CurlOO::Multi::CURL_SOCKET_TIMEOUT );
	};

	if ( $timeout_ms < 0 ) {
		if ( $multi->handles ) {
			$multi->{timer} = Irssi::timeout_add( 10000, $cb, '' );
		}
	} else {
		$multi->{timer} = Irssi::timeout_add_once( $timeout_ms, $cb, '' );
	}

	return 1;
}

sub add_handle($$)
{
	my $multi = shift;
	my $easy = shift;

	die "easy cannot finish()\n"
		unless $easy->can( 'finish' );

	Irssi::timeout_add_once( 10, sub {
		$multi->socket_action();
	}, '' );

	$multi->{active} = -1;
	$multi->SUPER::add_handle( $easy );
}

# perform and call any callbacks that have finished
sub socket_action
{
	my $multi = shift;

	my $active = $multi->SUPER::socket_action( @_ );
	return if $multi->{active} == $active;

	$multi->{active} = $active;

	while ( my ( $msg, $easy, $result ) = $multi->info_read() ) {
		if ( $msg == WWW::CurlOO::Multi::CURLMSG_DONE ) {
			$multi->remove_handle( $easy );
			$easy->finish( $result );
		} else {
			die "I don't know what to do with message $msg.\n";
		}
	}
}


my $multi;
sub WWW::CurlOO::Multi::add($)
{
	unless ( $multi ) {
		$multi = __PACKAGE__->new();
	}
	$multi->add_handle( shift );
}


package Irssi::CurlOO::Easy;
use strict;
use warnings;
use WWW::CurlOO::Easy qw(/^CURLOPT_/);
use base qw(WWW::CurlOO::Easy);

sub new
{
	my $class = shift;
	my $uri = shift;
	my $cb = shift;

	my $easy = $class->SUPER::new(
		{ body => '', headers => '' }
	);
	$easy->setopt( CURLOPT_WRITEHEADER, \$easy->{headers} );
	$easy->setopt( CURLOPT_FILE, \$easy->{body} );
	$easy->setopt( CURLOPT_TIMEOUT, 300 );
	$easy->setopt( CURLOPT_CONNECTTIMEOUT, 60 );
	$easy->setopt( CURLOPT_MAXREDIRS, 20 );
	$easy->setopt( CURLOPT_FOLLOWLOCATION, 1 );
	$easy->setopt( CURLOPT_ENCODING, 'gzip,deflate' );
	$easy->setopt( CURLOPT_SSL_VERIFYPEER, 0 );
	$easy->setopt( CURLOPT_COOKIEFILE, '' );
	$easy->setopt( CURLOPT_USERAGENT, 'Irssi + WWW::CurlOO' );

	return $easy;
}

sub finish
{
	my ( $easy, $result ) = @_;
	$easy->{referer} = $easy->getinfo( WWW::CurlOO::Easy::CURLINFO_EFFECTIVE_URL );

	my $cb = $easy->{cb};
	$cb->( $easy, $result );
}

sub _common_add
{
	my ( $easy, $uri, $cb ) = @_;
	if ( $easy->{referer} ) {
		$easy->setopt( CURLOPT_REFERER, $easy->{referer} );
	}
	$easy->setopt( CURLOPT_URL, $uri );
	$easy->{uri} = $uri;
	$easy->{cb} = $cb;
	$easy->{body} = '';
	$easy->{headers} = '';
	WWW::CurlOO::Multi::add( $easy );
}

sub get
{
	my ( $easy, $uri, $cb ) = @_;
	$easy->setopt( CURLOPT_HTTPGET, 1 );
	$easy->_common_add( $uri, $cb );
}

sub head
{
	my ( $easy, $uri, $cb ) = @_;
	$easy->setopt( CURLOPT_NOBODY, 1 );
	$easy->_common_add( $uri, $cb );
}

sub post
{
	my ( $easy, $uri, $cb, $post ) = @_;
	$easy->setopt( CURLOPT_POST, 1 );
	$easy->setopt( CURLOPT_POSTFIELDS, $post );
	$easy->setopt( CURLOPT_POSTFIELDSIZE, length $post );
	$easy->_common_add( $uri, $cb );
}


sub Irssi::downloader
{
	return __PACKAGE__->new();
}

=head2 EXAMPLE SCRIPT

 use strict;
 use warnings;
 use Irssi;
 use IO::File;
 use URI::Escape;

 Irssi::command( '/script load downloader.pl' );

 sub got_body
 {
     my ( $window, $easy, $result ) = @_;
     if ( $result ) {
         warn "Could not download $easy->{uri}: $result\n";
         return;
     }

     my @found;
     while ( $easy->{body} =~ s#<h2 class=sr><a href="(.*?)"><b>(.*?)</b></a></h2>## ) {
         my $uri = $1;
         $_ = $2;
         s/&#(\d+);/chr $1/eg;
         chomp;
         push @found, $_;
     }
     @found = "no results" unless @found;
     my $msg = "CPAN search %9$easy->{args}%n: " . (join "%9;%n ", @found);
     if ( $window ) {
         $window->print( $msg );
     } else {
         Irssi::print( $msg );
     }
 }

 sub cpan_search
 {
     my ( $args, $server, $window ) = @_;

     my $query = uri_escape( $args );
     my $uri = "http://search.cpan.org/search?query=${query}&mode=all";
     my $easy = Irssi::downloader();
     $easy->{args} = $args;
     $easy->get( $uri, sub { got_body( $window, @_ ) } );
 }

 Irssi::command_bind( 'cpan', \&cpan_search );

=cut
