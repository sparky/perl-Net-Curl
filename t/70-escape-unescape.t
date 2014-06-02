use strict;
use warnings;
use utf8;

use Test::More;
use Net::Curl::Easy;

BEGIN {
plan skip_all => "escape() and unescape() are not available untill version 7.15.04"
    if Net::Curl::LIBCURL_VERSION_NUM() < 0x070F04;
}

my $easy = Net::Curl::Easy->new();

my $tests = [
    [undef, undef],
    ["", ""],
    ["\0", "%00"],
    ["foo\0bar", "foo%00bar"],
    ["тестовое сообщение", "%D1%82%D0%B5%D1%81%D1%82%D0%BE%D0%B2%D0%BE%D0%B5%20%D1%81%D0%BE%D0%BE%D0%B1%D1%89%D0%B5%D0%BD%D0%B8%D0%B5"],
    ["~`!@#\$%^&*()-_=+{}[];:'\"<>,./?\\|\n\r\t", "~%60%21%40%23%24%25%5E%26%2A%28%29-_%3D%2B%7B%7D%5B%5D%3B%3A%27%22%3C%3E%2C.%2F%3F%5C%7C%0A%0D%09"],
];

plan tests => @$tests * 2;

for my $test(@$tests) {
    my $raw = $test->[0];
    my $escaped = $test->[1];

    my $just_escaped = $easy->escape($raw);
    is($just_escaped, $escaped, "escape");

    my $just_unescaped = $easy->unescape($escaped);
    is($just_unescaped, $raw, "unescape");
}
