use strict;
use warnings;
use lib 'inc';
use Test::More;
use Net::Curl::Easy qw(:constants);

plan tests => 1;

my $easy = Net::Curl::Easy->new();
eval { $easy->setopt(CURLOPT_COOKIEFILE, '') };
ok((not $@), 'checking if libcurl was compiled with COOKIES feature');
