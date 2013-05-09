#!perl -w
use strict;
use warnings;
use Test::More tests => 4;

use Net::Curl::Easy;
use Net::Curl::Share;
use Net::Curl::Multi;
use Net::Curl::Form;

eval { Net::Curl::Easy->no_such_method0 };
like $@, qr/\b no_such_method0 \b/xms;

eval { Net::Curl::Share->no_such_method1 };
like $@, qr/\b no_such_method1 \b/xms;

eval { Net::Curl::Multi->no_such_method2 };
like $@, qr/\b no_such_method2 \b/xms;

eval { Net::Curl::Form->no_such_method3 };
like $@, qr/\b no_such_method3 \b/xms;
