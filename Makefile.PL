use strict;
use warnings;

use ExtUtils::MakeMaker;
use ExtUtils::MakeMaker::Config;
use File::Find;

# you can set those manually if curl-config is not working for you
my %curl = (
	incdir => '',	# /some/path (where curl/curl.h is)
	cflags => '',	# -I/some/path
	libs => '',	# -lcurl
	version => ''	# 7.21.0
);

my $www_compat = 1;
# 0, "" - no WWW::Curl compat
# "exp" - explicit compatibility modules, will conflict with WWW::Curl
# true  - compat through Net::Curl::Compat (default)
if ( exists $ENV{WWW_COMPAT} ) {
	$www_compat = $ENV{WWW_COMPAT};
}

# - this version added curl_multi_socket_action() and many symbols
my $minimum_libcurl_ver = "7.15.5";
my $constant_names;

# XXX: some compilers may not support those flags
my $devel_cflags = "-Wall ";
#$devel_cflags .= "-Werror -DCALLBACK_TYPECHECK " if -d ".git";

if ( $curl{libs} and $curl{version} ) {
	print "Using manually introduced curl options:\n";
	while ( my ($k, $v) = each %curl ) {
		printf " %8s => %s\n", $k, $v;
	}
} else {
	eval {
		require ExtUtils::PkgConfig;
		my $pkgconfig = `which curl`;
		unless ( $? ) {
			chomp $pkgconfig;
			$pkgconfig =~ s/\bbin(.+?)curl$/lib$1pkgconfig/i;
			$ENV{PKG_CONFIG_PATH} = $pkgconfig;
		} else {
			print STDERR "which failed:\n$@\n";
		}
		%curl = ExtUtils::PkgConfig->find( 'libcurl' );
		$curl{version} = $curl{modversion};
	};
	if ( $@ ) {
		print STDERR "pkgconfig failed:\n$@\n";

		eval {
			%curl = get_curl_config();
			$curl{version} =~ s/libcurl\s//;
		};
		if ( $@ ) {
			print STDERR "curl-config failed:\n$@\n\n",
				"libcurl development fils do not seem to be available\n",
				"You must install libcurl $minimum_libcurl_ver or newer to\n",
				"build this module\n\n";
			print STDERR "NA: Unable to build distribution on this platform.\n";
			exit 0;
		}
	}

	print "Found libcurl version $curl{version}\n";

	(my $ver_to_cmp = $curl{version}) =~ s/[^\d]*$//;
	if ( eval "v$ver_to_cmp lt v$minimum_libcurl_ver" or $@ ) {
		print STDERR
			"Your currently installed libcurl version - $curl{version} - is too old.\n".
			"This module does not support libcurl older than $minimum_libcurl_ver\n\n";
		print STDERR "NA: Unable to build distribution on this platform.\n";
		exit 0;
	}
}

my $constant_names_sym = get_constants_symbols( $curl{version} );
eval {
	$curl{incdir} = get_curl_incdir();
	$constant_names = get_constants_headers( $curl{cflags},
		$curl{incdir} . "/curl/curl.h",
		-f $curl{incdir} . "/curl/multi.h" ? $curl{incdir} . "/curl/multi.h" : ()
	);
};
if ( $@ ) {
	warn "Cannot extract constants from header files: $@";
	warn "Using symbols-in-versions instead\n";
	$constant_names = $constant_names_sym;
}

{
	my $cn = scalar @$constant_names;
	my $cns = scalar @$constant_names_sym;

	my %cn;
	@cn{ @$constant_names } = ( 1 ) x scalar @$constant_names;
	foreach my $cnt ( @$constant_names_sym ) {
		print "$cnt missing\n" unless $cn{ $cnt };
	}

	my %cns;
	@cns{ @$constant_names_sym } = ( 1 ) x scalar @$constant_names_sym;
	foreach my $cnt ( @$constant_names ) {
		print "$cnt unexpected\n" unless $cns{ $cnt };
	}
	die "Found only $cn constants, there should be at least $cns\n"
		if $cn < $cns;
	print "-> found $cn constants (should be $cns)\n";
}
my @constant_types = divide_constants();

write_defenums( "const-defenums-h.inc" );

write_constants( "", $constant_types[ 0 ] );
write_constants( "Easy", $constant_types[ 1 ] );
write_constants( "Form", $constant_types[ 2 ] );
write_constants( "Multi", $constant_types[ 3 ] );
write_constants( "Share", $constant_types[ 4 ] );
split_xs( "Easy" );
split_xs( "Form" );
split_xs( "Multi" );
split_xs( "Share" );

write_examples_pod( 'lib/Net/Curl/examples.pod' );
if ( $www_compat ) {
	if ( $www_compat eq "exp" ) {
		deep_copy( 'inc/Compat/WWW', 'lib' );
		open my $f, '>', 'lib/Net/Curl/Compat.pm';
		print $f "'compat is explicit';\n";
	} else {
		write_compat_maybe( 'lib/Net/Curl/Compat.pm', 'inc/Compat' );
	}
} else {
	open my $f, '>', 'lib/Net/Curl/Compat.pm';
	print $f qq[die "WWW::Curl compatibility disabled\\n";\n];
}

my $bits = (length(pack(p => 0)) < 8)
    ? ' -D_FILE_OFFSET_BITS=64'
    : '';

# older perl seems to choke on it, maybe utf8::upgrade would work ?
my ($l_, $a_) = ($] >= 5.010) ? ("\x{142}", "\x{e1}") : qw(l a);
WriteMakefile(
	NAME 		=> 'Net::Curl',
	VERSION_FROM	=> 'lib/Net/Curl.pm',
	ABSTRACT_FROM	=> 'lib/Net/Curl.pm',
	AUTHOR		=> "Przemys${l_}aw Iskra <sparky at pld-linux.org>",
	CCFLAGS		=> $devel_cflags . $curl{cflags} . $bits,
	LIBS		=> $curl{libs},
	SIGN		=> 1,
	LICENSE		=> 'mit',
	META_MERGE	=> {
		recommends		=> {
			"ExtUtils::PkgConfig" => 0,
			"XSLoader" => 0,
		},
		resources		=> {
			bugtracker	=> 'https://github.com/sparky/perl-Net-Curl/issues',
			homepage	=> 'https://github.com/sparky/perl-Net-Curl',
			repository	=> 'git://github.com/sparky/perl-Net-Curl.git',
		},
		x_contributors	=> [
			"B${a_}lint Szilakszi",
			"Fuji, Goro",
			"Przemys${l_}aw Iskra",
			"Stanislaw Pusep",
		],
	},
	MIN_PERL_VERSION => 5.008001,
	CONFIGURE_REQUIRES => {
		"ExtUtils::MakeMaker::Config" => 0,
	},
	PREREQ_PM 	=> {
		"Carp" => 0,
		"DynaLoader" => 0,
		"Exporter" => 0,
		"overload" => 0,
		"strict" => 0,
		"warnings" => 0,
	},
	depend		=> {
		'Makefile'	=> '$(VERSION_FROM)',
		'$(FIRST_MAKEFILE)' => join ( " ", qw(Curl_Easy.xsh Curl_Form.xsh
			Curl_Multi.xsh Curl_Share.xsh Curl_Easy_setopt.c
			Curl_Easy_callbacks.c inc/symbols-in-versions),
			glob "examples/*.pl" ),
	},
	clean		=> {
		FILES => join " ", qw(const-*.inc curl-*.inc lib/WWW
			lib/Net/Curl/examples.pod lib/Net/Curl/Compat.pm),
	},
	DIR			=> [], # no other Makefile.PL
);

exit 0;

sub get_curl_config
{
	my $curl_config = $ENV{CURL_CONFIG} || 'curl-config';
	print "Using $curl_config script.\n";
	my %cc;
	foreach my $opt ( qw(vernum version prefix cflags libs) ) {
		my $ret = `${curl_config} --$opt`;
		if ( $? ) {
			die "Execution ${curl_config} --$opt failed.\n" .
				"is your libcurl installed correctly ?\n";
		}
		chomp $ret;
		$cc{ $opt } = $ret;
		# print "${curl_config} --$opt: $ret\n";
	}
	return %cc;
}

sub get_curl_incdir
{
	my @incpath = (
		( defined $curl{incdir} ? $curl{incdir} : () ),
		( $curl{cflags} =~ /-I(\S+)/g ),
		( "$curl{prefix}/include" ),
		( split /\s+/, $Config{usrinc} ),
		( split /\s+/, $Config{locincpth} ),
		qw(
		/usr/include
		/usr/local/include
		/usr/local/curl/include
		/usr/local/include/curl
		)
	);

	foreach my $inc ( @incpath ) {
		if ( -f $inc . "/curl/curl.h") {
			return $inc;
		}
	}

	die "Cannot find curl/curl.h\n";
}

sub get_constants_symbols
{
	my $curlver = shift;
	$curlver =~ s/libcurl\s+//;
	$curlver =~ s/[^\d]*$//;
	my $cver = eval "v$curlver";

	my %out;

	open my $fin, "<", "inc/symbols-in-versions"
		or die "Cannot open symbols file: $!\n";
	while ( <$fin> ) {
		next if /^\s+/;
		next if /^\s*$/;
		my ( $sym, $in, $dep, $out ) = split /\s+/, $_;

		if ( $out ) {
			my $vout = eval "v$out";
			next if $cver ge $vout;
		}

		if ( $in ne "-" ) {
			my $vin = eval "v$in";
			next unless $cver ge $vin;
		}

		$out{ $sym } = 1;
	}

	my @out = sort keys %out;
	return \@out;
}

sub get_constants_headers
{
	my %syms;
	my $cflags = shift;

	foreach my $curl_h ( @_ ) {
		print "Reading $curl_h ($Config{cpprun} $cflags $curl_h)\n";
		open( H_IN, "-|", "$Config{cpprun} $cflags $curl_h" )
			or die "Cannot run $Config{cpprun} $curl_h: $@\n";
		while ( <H_IN> ) {
			if ( /enum\s+(\S+\s+)?{/ .. /}/ ) {
				s/^\s+//;
				next unless /^CURL/;
				chomp;
				s/[,\s].*//;
				s/=.*$//;
				next unless /^\w+$/;
				$syms{ $_ } = 1;
			}
		}
		close H_IN;

		open (H, "<", $curl_h)
			or die "Cannot open $curl_h: ".$!;
		while(<H>) {
			if (/^#define (CURL[A-Za-z0-9_]*)/) {
				$syms{ $1 } = 1;
			}
		}
		close H;
	}

	my @out;
	foreach my $e (sort keys %syms) {
		if ( $e =~ /(OBSOLETE|^CURL_EXTERN|_LAST\z|_LASTENTRY\z|^CURL_FORMAT_OFF_T$|^CURL_ISOCPP$)/ ) {
			next;
		}
		push @out, $e;
	}

	return \@out;
}

sub divide_constants
{
	my @out = ();

	foreach ( @$constant_names ) {
		my $list = 1; # Easy
		$list = 0 if /^CURL_?VERSION/; # main
		$list = 2 if /^CURL_?FORM/; # Form
		$list = 3 if /^CURL(M_|MSG_|MOPT_|_POLL_|_CSELECT_|_SOCKET_TIMEOUT)/; # Multi
		$list = 4 if /^(CURLSHOPT_|CURL_LOCK_)/; # Share
		push @{ $out[ $list ] }, $_;
	}
	return @out;
}

sub split_xs
{
	my $name = shift;
	my $in = "Curl_$name.xsh";

	open my $fin, '<', $in
		or die "Can't open $in: $!\n";

	my $outc = "curl-$name-c.inc";
	open my $foutc, '>', $outc
		or die "Can't create $outc: $!\n";
	print "Writing $outc\n";

	my $outxs = "curl-$name-xs.inc";
	open my $foutxs, '>', $outxs
		or die "Can't create $outxs: $!\n";
	print "Writing $outxs\n";

	while ( <$fin> ) {
		if ( /^MODULE\s*=.*PACKAGE/ ) {
			print $foutxs $_;
			print $foutxs @_ = <$fin>;
			last;
		} else {
			print $foutxs "\n";
			print $foutc $_;
		}
	}
}

sub write_constants
{
	my $name = shift;
	my $constants = shift;

	my $lname = $name ? lc $name : 'curl';
	my $out = "const-$lname-xs.inc";
	print "Writing $out\n";

	open my $foutxs, '>', $out
		or die "Can't create $out: $!\n";

	$name .= '::' if $name;
	my $symbol_table = "Net::Curl::$name";
	print $foutxs <<"EOBOOT";
BOOT:
	{
		dTHX;
		HV *symbol_table = get_hv( "$symbol_table", GV_ADD );
		static const struct iv_s values_for_iv[] = {
EOBOOT
	foreach my $c ( sort @$constants ) {
		printf $foutxs qq[\t\t\t{ "%s", %d, %s },\n], $c, length $c, $c;
	}
	print $foutxs <<'EOBOOT';
			{ NULL, 0, 0 }
		};
		const struct iv_s *value_for_iv = values_for_iv;
		while ( value_for_iv->name ) {
			perl_curl_constant_add(aTHX_ symbol_table, value_for_iv->name,
				value_for_iv->namelen, newSViv( value_for_iv->value ) );
			++value_for_iv;
		}

		++PL_sub_generation;
	}
EOBOOT

}

sub write_defenums
{
	my $out = shift;

	print "Writing $out\n";
	open my $o, ">", $out;
	foreach ( @$constant_names ) {
		print $o "#ifndef $_\n";
		print $o "# define $_ $_\n";
		print $o "#endif\n";
	}
	close $o;
}


sub write_examples_pod
{
	my $out = shift;

	print "Writing $out\n";
	open my $o, ">", $out;
	print $o "=head1 NAME\n\n";
	print $o "Net::Curl::examples - sample modules and test code for Net::Curl\n\n";

	foreach my $script ( sort glob "examples/*.pl" ) {
		my $nopod = 0;
		my $code = 1;

		print "<- $script\n";

		open my $fin, '<', $script
			or die "Cannot open $script: $!\n";

		while ( <$fin> ) {
			if ( /^=cut/ ) {
				$code = 1;
				next;
			} elsif ( /^=/ ) {
				$code = 0;
			} elsif ( /^#nopod/ ) {
				$nopod = 1;
				next;
			} elsif ( /^#endnopod/ ) {
				$nopod = 0;
				next;
			} elsif ( $nopod ) {
				next;
			}
			$_ = " " . $_ if $code;
			s/^\t/ /;
			s/\t/    /g;
			s/ +$//;
			print $o $_;
			if ( /^=head1\s/ ) {
				print $o "\n=head4 I<Extracted from C<$script>>\n";
			}
		}

		print $o "\n=cut\n";
	}
}

sub write_compat_maybe
{
	my ( $name_out, $name_in ) = @_;

	return unless -r $name_in;

	open my $fout, '>', $name_out
		or die "Cannot write to $name_out: $!\n";
	print "Writing $name_out\n";

	my @pm;
	find( sub{ push @pm, $File::Find::name if /\.pm$/ }, $name_in );

	local $/ = undef;
	my $data = "";
	my @sections;
	foreach ( sort @pm ) {
		open my $fin, '<', $_ or die;
		s#\Q$name_in\E/##;
		my $pos = length $data;
		push @sections, "\t'$_' => $pos,";
		$data .= <$fin> . "\n__END__\n\n";
	}

	open my $fin, '<', $name_in . ".pm" or die;
	$_ = <$fin>;
	local $" = "\n";
	s/#MODULES#/@sections/;

	print $fout $_ . $data;
}

sub deep_copy
{
	my ( $src, $dst ) = @_;

	system "cp", "-a", $src, $dst;
	if ( $? ) {
		require File::Copy::Recursive;
		( my $name = $src ) =~ s#.*/##;
		File::Copy::Recursive::dircopy( $src, "$dst/$name" );
	}
}

sub MY::postamble
{
	return <<'EOM';
.PHONY: testall disttestall version_update symbols_update test_update inc_update
testall:
	AUTOMATED_TESTING=1 AUTHOR_TESTING=1 EXTENDED_TESTING=1 $(MAKE) test

disttestall:
	AUTOMATED_TESTING=1 AUTHOR_TESTING=1 EXTENDED_TESTING=1 $(MAKE) disttest

version_update:
	sed -i "/VERSION\s*=/s/=\s*'.*'/= '$(VERSION)'/" lib/Net/Curl/*.pm

symbols_update:
	curl https://github.com/bagder/curl/raw/master/docs/libcurl/symbols-in-versions -o inc/symbols-in-versions

test_update:
	curl https://github.com/sparky/perl-Test-HTTP-Server/raw/master/lib/Test/HTTP/Server.pm -o inc/Test/HTTP/Server.pm

inc_update: symbols_update test_update
EOM
}

__END__
package ExtUtils::MM_Unix;

sub all_target {
	my $self = shift;
	return <<'MAKE_EXT';
all :: pure_all manifypods
	$(NOECHO) echo "Module loads OK ?"
	$(PERLRUNINST) -le 'use Net::Curl; print Net::Curl::LIBCURL_VERSION'
	$(NOECHO) $(NOOP)
MAKE_EXT

}


# vim: ts=4:sw=4
