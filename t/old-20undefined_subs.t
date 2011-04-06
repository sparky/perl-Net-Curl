#!perl -w
use strict;
use Test::More tests => 4;

use WWW::CurlOO::Easy;
use WWW::CurlOO::Share;
use WWW::CurlOO::Multi;
use WWW::CurlOO::Form;

eval { WWW::CurlOO::Easy->no_such_method0 };
like $@, qr/\b no_such_method0 \b/xms;

eval { WWW::CurlOO::Share->no_such_method1 };
like $@, qr/\b no_such_method1 \b/xms;

eval { WWW::CurlOO::Multi->no_such_method2 };
like $@, qr/\b no_such_method2 \b/xms;

eval { WWW::CurlOO::Form->no_such_method3 };
like $@, qr/\b no_such_method3 \b/xms;
