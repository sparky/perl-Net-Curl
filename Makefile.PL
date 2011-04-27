use strict;
use ExtUtils::MakeMaker;
use ExtUtils::MakeMaker::Config;

# you can set those manually if curl-config is not working for you
my %curl = (
	incdir => '',	# /some/path (where curl/curl.h is)
	cflags => '',	# -I/some/path
	libs => '',	# -lcurl
	version => ''	# 7.21.0
);


# - this version added curl_multi_socket_action() and many symbols
my $minimum_libcurl_ver = "7.15.4";
my $constant_names;

# XXX: some compilers may not support those flags
my $devel_cflags = "-Wall ";
$devel_cflags .= "-Werror -DCALLBACK_TYPECHECK " if -d ".git";

if ( $curl{libs} and $curl{version} ) {
	print "Using manually introduced curl options:\n";
	while ( my ($k, $v) = each %curl ) {
		printf " %8s => %s\n", $k, $v;
	}
} else {
	eval {
		require ExtUtils::PkgConfig;
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

	if ( eval "v$curl{version} lt v$minimum_libcurl_ver" or $@ ) {
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

write_examples_pod( 'lib/WWW/CurlOO/examples.pod' );

# older perl seems to choke on it, maybe utf8::upgrade would work ?
my $l_ = $] >= 5.010 ? "ł" : "l";
WriteMakefile(
	NAME 		=> 'WWW::CurlOO',
	VERSION_FROM	=> 'lib/WWW/CurlOO.pm',
	ABSTRACT_FROM	=> 'lib/WWW/CurlOO.pm',
	AUTHOR		=> "Przemys${l_}aw Iskra <sparky at pld-linux.org>",
	META_MERGE	=> {
		resources => {
			repository => 'https://github.com/sparky/perl-WWW-CurlOO'
		},
	},
	CCFLAGS		=> $devel_cflags . $curl{cflags},
	LIBS		=> $curl{libs},
	SIGN		=> 1,
	LICENSE		=> 'mit',
	MIN_PERL_VERSION => 5.008001,
	CONFIGURE_REQUIRES => {
		"ExtUtils::MakeMaker" => 0,
		"ExtUtils::MakeMaker::Config" => 0,
		#"ExtUtils::PkgConfig" => 0,
	},
	PREREQ_PM => {
		"Test::More" => 0,
		"Test::CPAN::Meta" => 0,
		"Test::Pod" => 0,
		"File::Temp" => 0,
		"Scalar::Util" => 0,
	},
	depend		=> {
		'Makefile'	=> '$(VERSION_FROM)',
		'$(FIRST_MAKEFILE)' => join ( " ", qw(CurlOO_Easy.xsh CurlOO_Form.xsh
			CurlOO_Multi.xsh CurlOO_Share.xsh CurlOO_Easy_setopt.c
			CurlOO_Easy_callbacks.c inc/symbols-in-versions),
			glob "examples/*.pl" ),
	},
	clean		=> {
		FILES => 'const-*.inc curloo-*.inc lib/WWW/CurlOO/examples.pod'
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
	my $in = "CurlOO_$name.xsh";

	open my $fin, '<', $in
		or die "Can't open $in: $!\n";

	my $outc = "curloo-$name-c.inc";
	open my $foutc, '>', $outc
		or die "Can't create $outc: $!\n";
	print "Writing $outc\n";

	my $outxs = "curloo-$name-xs.inc";
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
	my $symbol_table = "WWW::CurlOO::$name";
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
	print $o "WWW::CurlOO::examples - sample modules and test code for WWW::CurlOO\n\n";

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

		print $o "\n\n";
	}
}

sub MY::postamble
{
	return <<'EOM';
.PHONY: testall disttestall symbols_update
testall:
	TEST_AUTHOR=1 TEST_EXTENDED=1 $(MAKE) test

disttestall:
	TEST_AUTHOR=1 TEST_EXTENDED=1 $(MAKE) disttest

symbols_update:
	curl https://github.com/bagder/curl/raw/master/docs/libcurl/symbols-in-versions -o inc/symbols-in-versions
EOM
}

__END__
package ExtUtils::MM_Unix;

sub all_target {
	my $self = shift;
	return <<'MAKE_EXT';
all :: pure_all manifypods
	$(NOECHO) echo "Module loads OK ?"
	$(PERLRUNINST) -le 'use WWW::CurlOO; print WWW::CurlOO::LIBCURL_VERSION'
	$(NOECHO) $(NOOP)
MAKE_EXT

}


# vim: ts=4:sw=4
