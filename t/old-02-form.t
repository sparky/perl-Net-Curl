#!perl
use strict;
use warnings;
use Test::More tests => 11;

use Net::Curl::Form qw(:constants);

my $form = Net::Curl::Form->new();

eval {
	$form->add(
		CURLFORM_COPYNAME() => "name",
		CURLFORM_COPYCONTENTS() => "content\0binary"
	);
};
ok( (not $@), "1. add simple contents" );

eval {
	$form->add(
		CURLFORM_COPYNAME() => "name",
		CURLFORM_NAMELENGTH() => 2,
		CURLFORM_COPYCONTENTS() => "content",
		CURLFORM_CONTENTSLENGTH() => 4,
	);
};
ok( (not $@), "2. add simple contents with length" );

eval {
	$form->add(
		CURLFORM_COPYNAME, "htmlcode",
		CURLFORM_COPYCONTENTS, "<HTML></HTML>",
		CURLFORM_CONTENTTYPE, "text/html"
	);
};
ok( (not $@), "3. add with content type" );

eval {
	$form->add(
		CURLFORM_COPYNAME, "license",
		CURLFORM_FILE, "LICENSE"
	);
};
ok( (not $@), "4. add file" );

eval {
	$form->add(
		CURLFORM_COPYNAME, "license",
		CURLFORM_FILE, "LICENSE",
		CURLFORM_CONTENTTYPE, "text/plain"
	);
};
ok( (not $@), "5. add file and content type" );

eval {
	$form->add(
		CURLFORM_COPYNAME, "tests",
		map { CURLFORM_FILE(), $_ } <t/*.t>
	);
};
ok( (not $@), "6. add multiple files" );

eval {
	$form->add(
		CURLFORM_COPYNAME, "filecontent",
		CURLFORM_FILECONTENT, "MANIFEST"
	);
};
ok( (not $@), "7. add contents from file" );

eval {
	$form->add(
		CURLFORM_FILECONTENT, "MANIFEST"
	);
};
ok( $@ == CURL_FORMADD_INCOMPLETE, "8. missing name" );

eval {
	$form->get( undef );
};
ok( $@, "invalid get died" );

my $buffer;
eval {
	$form->get( $buffer = "" );
};
ok( (not $@), "correct serialization" );

ok( length $buffer > 10000, "buffer is filled with lots of data" );
