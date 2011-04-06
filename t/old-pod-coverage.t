#!perl

use Test::More;
unless ( $ENV{'TEST_AUTHOR'} ) {
	my $msg = 'Author test.  Set $ENV{TEST_AUTHOR} to a true value to run.';
	plan skip_all => $msg;
}

eval "use Test::Pod::Coverage 1.04";
plan skip_all => "Test::Pod::Coverage 1.04 required for testing POD coverage" if $@;
plan tests => 1;
pod_coverage_ok('WWW::CurlOO','WWW::CurlOO has proper POD coverage');
