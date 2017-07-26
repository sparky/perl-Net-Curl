use strict;
use warnings;

use Test::More;
use Net::Curl::Easy;

BEGIN {
plan skip_all => "escape() and unescape() are not available untill version 7.15.4"
    if Net::Curl::LIBCURL_VERSION_NUM() < 0x070F04;
}

my $easy = Net::Curl::Easy->new();

my $tests = [
    [undef, undef],
    ["", ""],
    ["0", "0"],
    [0, "0"],
    ["0 but true", "0%20but%20true"],
    ["\0", "%00"],
    ["foo\0bar", "foo%00bar"],
    ["тестовое сообщение", "%D1%82%D0%B5%D1%81%D1%82%D0%BE%D0%B2%D0%BE%D0%B5%20%D1%81%D0%BE%D0%BE%D0%B1%D1%89%D0%B5%D0%BD%D0%B8%D0%B5", 0],
    ["тестовое сообщение", "%D1%82%D0%B5%D1%81%D1%82%D0%BE%D0%B2%D0%BE%D0%B5%20%D1%81%D0%BE%D0%BE%D0%B1%D1%89%D0%B5%D0%BD%D0%B8%D0%B5", 1],
    ["`!@#\$%^&*()=+{}[];:'\"<>,/?\\|\n\r\t", "%60%21%40%23%24%25%5E%26%2A%28%29%3D%2B%7B%7D%5B%5D%3B%3A%27%22%3C%3E%2C%2F%3F%5C%7C%0A%0D%09"],
    ["a\xffb\xfec\xf0d", "a%FFb%FEc%F0d"],
];

my $is_centos = 0;
if (open(my $fh, '<', '/etc/redhat-release')) {
    my $rh = <$fh>;
    chomp $rh;
    $is_centos = 1
        if $rh =~ /^CentOS/i;
    close $fh;
}

unless ($is_centos) {
    # libcurl version 7.21.2 and newer do not escape those characters, older versions do
    push @$tests, ["~-_.", Net::Curl::LIBCURL_VERSION_NUM() < 0x071502 ? "%7E%2D%5F%2E" : "~-_."],
}

plan tests => @$tests * 2;

foreach my $test ( @$tests ) {
    my ( $raw, $escaped, $utf8 ) = @$test;
    utf8::decode( $raw ) if $utf8;

    my $just_escaped = $easy->escape( $raw );
    is( $just_escaped, $escaped, "escape" );

    my $just_unescaped = $easy->unescape( $escaped );
    utf8::decode( $just_unescaped ) if $utf8;
    is( $just_unescaped, $raw, "unescape" );
}
