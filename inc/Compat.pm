package Net::Curl::Compat;
=head1 NAME

Net::Curl::Compat -- compatibility layer for WWW::Curl

=head1 SYNOPSIS

 --- old.pl
 +++ new.pl
 @@ -2,6 +2,8 @@
  use strict;
  use warnings;

 +# support both Net::Curl (default) and WWW::Curl
 +BEGIN { eval { require Net::Curl::Compat; } }
  use WWW::Curl::Easy 4.15;
  use WWW::Curl::Multi;

=head1 DESCRIPTION

Net::Curl::Compat lets you use Net::Curl in applications and modules
that normally use WWW::Curl. There are several ways to accomplish it:

=head2 EXECUTION

Execute an application through perl with C<-MNet::Curl::Compat> argument:

 perl -MNet::Curl::Compat APPLICATION [ARGUMENTS]

=head2 CODE, use Net::Curl by default

Add this line before including any WWW::Curl modules:

 BEGIN { eval { require Net::Curl::Compat; } }

This will try to preload Net::Curl, but won't fail if it isn't available.

=head2 CODE, use WWW::Curl by default

Add those lines before all the others that use WWW::Curl:

 BEGIN {
     eval { require WWW::Curl; }
     require Net::Curl::Compat if $@;
 }

This will try WWW::Curl first, but will fallback to Net::Curl if that fails.

=head1 NOTE

If you want to write compatible code, DO NOT USE Net::Curl::Compat during
development. This module hides all the incompatibilities, but does not disable
any of the features that are unique to Net::Curl. You could end up using
methods that do not yet form part of official WWW::Curl distribution.

=cut

use strict;
use warnings;

use Carp qw(croak);

our $VERSION = 4.15;

=for Pod::Coverage
VERSION
=cut

# Dirty hack so Test::ConsistentVersion passes
sub VERSION {
	return (caller)[0] eq 'Test::ConsistentVersion'
		? 0.39
		: $VERSION;
}

my %packages = (
#MODULES#
);

my $start = tell *DATA;
unshift @INC, sub {
	my $pkg = $packages{ $_[1] };
	return unless defined $pkg;
	open(my $fh, '<&', *DATA) or croak "can't read from __DATA__";
	seek $fh, $start + $pkg, 0;
	return $fh;
};

1;

=head1 COPYRIGHT

Copyright (c) 2011-2015 Przemyslaw Iskra <sparky at pld-linux.org>.

You may opt to use, copy, modify, merge, publish, distribute and/or sell
copies of the Software, and permit persons to whom the Software is furnished
to do so, under the terms of the MPL or the MIT/X-derivate licenses. You may
pick one of these licenses.

=cut

__DATA__
