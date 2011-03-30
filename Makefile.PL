use strict;
use ExtUtils::MakeMaker;
use ExtUtils::MakeMaker::Config;
use ExtUtils::Constant 0.11 'WriteConstants';
use File::Path qw(make_path);

# you can set those manually if curl-config is not working for you
my %curl = (
	incdir => '',	# /some/path (where curl/curl.h is)
	cflags => '',	# -I/some/path
	libs => '',	# -lcurl
	version => ''	# 7.21.0
);


# - this version added curl_multi_socket_action() and many symbols
my $minimum_libcurl_verstr = "7.15.4";
my $minimum_libcurl_ver = 0x070f04;
my $constant_names;

if ( $curl{libs} and $curl{libs} ) {
	print "Using manually introduced curl options:\n";
	while ( my ($k, $v) = each %curl ) {
		printf " %8s => %s\n", $k, $v;
	}
} elsif ( $^O eq 'MSWin32' ) {
	print	"Sorry, no automated install is available on Windows,\n".
		"please see the README.Win32 file on instructions for a manual install.\n";
	exit 1;
} else {
	%curl = get_curl_config();
}

my $constant_names_sym = get_constants_symbols( $curl{version} );
eval {
	$constant_names = get_constants( $curl{cflags},
		$curl{incdir} . "/curl/curl.h",
		-f $curl{incdir} . "/curl/multi.h" ? $curl{incdir} . "/curl/multi.h" : ()
	);
};
if ( $@ ) {
	warn "Cannot extract constants from header files: $@\n";
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
	die "Found only $cn constants, there should be at least $cns\n"
		if $cn < $cns;
	print "-> found $cn constants (should be $cns)\n";
}
my @constant_types = divide_constants();

# WriteConstants does not honour enums, so we define those symbols
write_defenums( "const-defenums.h" );

make_path( "pplib/WWW/CurlOO" );
write_from_template( "CurlOO", $constant_types[ 0 ], "WWW" );
write_from_template( "Easy", $constant_types[ 1 ] );
write_from_template( "Form", $constant_types[ 2 ] );
write_from_template( "Multi", $constant_types[ 3 ] );
write_from_template( "Share", $constant_types[ 4 ] );

WriteConstants(
	($] > 5.009002 ? (PROXYSUBS => 1) : ()),
	NAME => 'WWW::CurlOO',
	NAMES => $constant_types[ 0 ],
	C_FILE => 'const-c.inc',
	XS_FILE => 'const-curl-xs.inc',
	XS_SUBNAME => 'curl_constant',
	C_SUBNAME => 'curl_constant',
);


WriteMakefile(
	NAME 		=> 'WWW::CurlOO',
	VERSION_FROM	=> 'pplib/WWW/CurlOO.pm',
	ABSTRACT_FROM	=> 'pplib/WWW/CurlOO.pm',
	AUTHOR		=> 'Przemysław Iskra <sparky at pld-linux.org>',
	META_MERGE	=> {
		resources => {
			repository => 'https://github.com/sparky/perl-WWW-CurlOO'
		},
	},
	CCFLAGS		=> $curl{cflags},
	LIBS		=> $curl{libs},
	SIGN		=> 1,
	LICENSE		=> 'MPL or MIT/X-derivate',	
	MIN_PERL_VERSION => 5.006001,
	PMLIBDIRS => [ 'pplib' ],
	PMLIBPARENTDIRS => [ 'pplib' ],
	depend		=> {
		'CurlOO.c' => 'CurlOO.xs CurlOO_Easy.xs CurlOO_Form.xs CurlOO_Multi.xs CurlOO_Share.xs'
	},
	clean		=> {
		FILES => 'const-c.inc const-*-xs.inc const-defenums.h'
	},
	realclean	=> {
		FILES => 'pplib',
	},
);

exit 0;

sub get_curl_config
{
	my $curl_config = $ENV{CURL_CONFIG} || 'curl-config';
	my %cc;
	foreach my $opt ( qw(vernum version prefix cflags libs) ) {
		my $ret = `${curl_config} --$opt`;
		if ( $? ) {
			print "Execution ${curl_config} --$opt failed.\n" .
				"is your curl installed correctly ?\n";
			exit 1;
		}
		chomp $ret;
		$cc{ $opt } = $ret;
		# print "${curl_config} --$opt: $ret\n";
	}

	print "Found libcurl version $cc{version}\n";
	
	if ( $cc{vernum} and hex( $cc{vernum} ) < $minimum_libcurl_ver) {
		print
			"Your currently installed libcurl version - $cc{version} - is too old.\n".
			"This module doesn't seek compatibility with versions older than $minimum_libcurl_verstr\n".
			"Proceed manually if you know what you're doing.\n";
		exit 1;
	}

	my @incpath = (
		( defined $curl{incdir} ? $curl{incdir} : () ),
		( $cc{cflags} =~ /-I(\S+)/g ),
		( "$cc{prefix}/include" ),
		( split /\s+/, $Config{usrinc} ),
		( split /\s+/, $Config{locincpth} ),
		qw(
		/usr/include
		/usr/local/include
		/usr/local/curl/include
		/usr/local/include/curl
		)
	);

	my $curl_d;
	foreach my $inc ( @incpath ) {
		if ( -f $inc . "/curl/curl.h") {
			$curl_d = $inc;
			last;
		}
	}

	die "Cannot find curl.h - cannot build constants files  - see Makefile.PL"
		unless defined $curl_d;

	$cc{incdir} = $curl_d;
	$cc{libs} ||= "-lcurl";
	return %cc;
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
		next if /^#\s+/;
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

sub get_constants
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
		if($e =~ /(OBSOLETE|^CURL_EXTERN|_LAST\z|_LASTENTRY\z)/) {
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

sub write_from_template
{
	my $name = shift;
	my $constants = shift;
	my $dir = shift;
	my $havedir = !!$dir;
	$dir ||= "WWW/CurlOO";

	my $template = "lib/$dir/$name.pm";
	my $out = "pplib/$dir/$name.pm";

	print "Writing $out from $template\n";
	open my $fout, ">", $out
		or die "Can't create $out\n";

	open my $fin, "<", $template
		or die "Can't read $template\n";

	local $_;
	while (<$fin>) {
		if (m/^\s*#\s*\@CURLOPT_INCLUDE\@/) {
			print $fout join "\n", 'qw(', @$constants, ')';
		} else {
			print $fout $_;
		}
	}

	return if $havedir;
	my $lname = lc $name;
	WriteConstants(
		($] > 5.009002 ? (PROXYSUBS => 1) : ()),
		NAME => "WWW::CurlOO::$name",
		NAMES => $constants,
		C_FILE => 'const-c.inc',
		XS_FILE => "const-$lname-xs.inc",
		XS_SUBNAME => "curl_${lname}_constant",
		C_SUBNAME => 'curl_constant',
	);

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

# vim: ts=4:sw=4
