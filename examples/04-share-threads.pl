=head1 Share::Threads

This module shows how one can share http cookies and dns cache between multiple
threads.

=head2 Motivation

Threads are evil, but some people think they are not. I want to make them a
favor and show how bad threads really are.

=head2 Limitations

=over

=item *

Net::Curl::Share is the only package that allows sharing between threads.
Others (Easy, Multi, Form) are usable only in their creating thread.

=item *

Share internals are always shared between threads, but you must mark your
base object as shared if you want to use the data elsewhere.

=item *

Shared Net::Curl::Share does not support lock and unlock callbacks.
However, locking is done internally, so no worries about corruption.

=item *

If we want to share the data, we cannot trigger all downloads at the same
time, because there would be no data to share at the time. This solution opts
to lock other downloads until headers from the server are fully received. It
assures cache coherency, but slows down overall application.

=item *

This method does not reuse persistent connections, it would be much faster
to get those 6 requests one after another than to doing all 6 in parallel.

=item *

If you share dns cache all connections for one domain will go to the same IP,
even if domain name resolves to multiple adresses.

=back

=head2 MODULE CODE

=cut
package Share::Threads;
use threads;
use threads::shared;
use Thread::Semaphore;
use Net::Curl::Share qw(:constants);
use base qw(Net::Curl::Share);


sub new
{
	my $class = shift;

	# we want our private data to be shareable
	my %base :shared;

	# create a shared share object
	my $self :shared = $class->SUPER::new( \%base );

	# share both cookies and dns
	$self->setopt( CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE );
	$self->setopt( CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS );

	# Net::Curl::Share locks each datum automatically, this will
	# prevent memory corruption.
	#
	# we use semaphore to lock share completely
	$self->{sem} = Thread::Semaphore->new();
	
	return $self;
}

# this locks way too much, but works as expected
sub lock
{
	my $share = shift;
	$share->{sem}->down();
	$share->{blocker} = threads->tid();
}

sub unlock
{
	my $share = shift;
	unless ( exists $share->{blocker} ) {
		warn "Tried to unlock share that wasn't locked\n";
		return;
	}
	unless ( $share->{blocker} == threads->tid() ) {
		warn "Tried to unlock share from another thread\n";
		return;
	}
	delete $share->{blocker};
	$share->{sem}->up();
}

1;

=head2 TEST Easy package

This Easy::Threads object will block whole share object for duration of dns
name resolution and until headers are completely received.

=cut
package Easy::Threads;
use strict;
use warnings;
use Net::Curl::Easy qw(/^CURLOPT_.*/);
use base qw(Net::Curl::Easy);

sub new
{
	my $class = shift;
	my $share = shift;

	my $easy = $class->SUPER::new( { body => '', head => '' } );
	$easy->setopt( CURLOPT_VERBOSE, 1 );
	$easy->setopt( CURLOPT_WRITEHEADER, \$easy->{head} );
	$easy->setopt( CURLOPT_FILE, \$easy->{body} );
	$easy->setopt( CURLOPT_HEADERFUNCTION, \&cb_header );
	$easy->setopt( CURLOPT_SHARE, $share );

	return $easy;
}

sub cb_header {
	my ( $easy, $data, $uservar ) = @_;

	if ( $data eq "\r\n" ) {
		# we have all the headers now, allow other threads to run
		$easy->share->unlock()
			unless $easy->{unlocked};

		$easy->{unlocked} = 1;
	}

	$$uservar .= $data;

	return length $data;
}

sub get
{
	my $easy = shift;
	my $uri = shift;

	$easy->setopt( CURLOPT_URL, $uri );
	$easy->{uri} = $uri;
	$easy->{body} = '';
	$easy->{head} = '';
	delete $easy->{unlocked};

	# lock share
	$easy->share->lock();

	# ok, now we can request
	eval {
		$easy->perform();
	};

	# There may have been some problem, make sure we unlock the share.
	# This should issue a warning, check $easy->{unlocked} to see
	# whether we really need to unlock.
	$easy->share->unlock();

	# return something
	return $easy->{body};
}

1;

=head2 TEST APPLICATION

Sample application using this module looks like this:

	#!perl
	use threads;
	use threads::shared;
	use strict;
	use warnings;
	use Share::Threads;
	use Easy::Threads;
#nopod
=cut
package main;
use strict;
use warnings;
#endnopod

my $share :shared = Share::Threads->new();

my @uri = (
	"http://www.google.com/search?q=perl",
	"http://www.google.com/search?q=curl",
	"http://www.google.com/search?q=perl+curl",
	"http://www.google.com/search?q=perl+threads",
	"http://www.google.com/search?q=curl+threads",
	"http://www.google.com/search?q=perl+curl+threads",
);

sub getone
{
	my $uri = shift;

	my $easy = Easy::Threads->new( $share );
	return $easy->get( $uri );
}

# start all threads
my @threads;
foreach my $uri ( @uri ) {
	push @threads, threads->create( \&getone, $uri );
	threads->yield();
}

# reap all threads
foreach my $t ( @threads ) {
	my $body = $t->join();
	my $len = length $body;
	print "DONE: [[[ $len ]]]\n";
}

#nopod
# vim: ts=4:sw=4
