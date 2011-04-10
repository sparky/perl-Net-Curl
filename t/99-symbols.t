#!perl
use strict;
use warnings;
use Test::More;

unless ( $ENV{'TEST_AUTHOR'} ) {
	my $msg = 'Author test.  Set $ENV{TEST_AUTHOR} to a true value to run.';
	plan skip_all => $msg;
}

my $cver = v7.15.4;
my @files = qw(
CurlOO.xs
CurlOO_Easy.xsh
CurlOO_Easy_setopt.c
CurlOO_Easy_callbacks.c
CurlOO_Form.xsh
CurlOO_Multi.xsh
CurlOO_Share.xsh
);

# extract constants which were introduced after $cver
my @check;
{
	open my $fin, "<", "inc/symbols-in-versions"
	    or die "Cannot open symbols file: $!\n";
	while ( <$fin> ) {
		next if /^#\s+/;
		next if /^\s+/;
		my ( $sym, $in, $dep, $out ) = split /\s+/, $_;

		if ( $in ne "-" ) {
			my $vin = eval "v$in";
			if ( $vin gt $cver ) {
				push @check, $sym;
			}
		}

	}
}

plan tests => scalar ( @files ) * scalar @check;

foreach my $file ( @files ) {
	open my $fin, '<', $file
		or die;
	my @lines = <$fin>;
	undef $fin;

	my $full = join "", @lines;

	foreach my $sym ( @check ) {
		unless ( $full =~ $sym ) {
			pass( "$sym symbol not used in $file" );
			next;
		}

		my $bad = 0;
		my @ifdef;
		foreach my $line ( @lines ) {
			if ( $line =~ /^\s*#\s*if(?:def\s+(\S+))?/ ) {
				push @ifdef, $1;
			} elsif ( $line =~ /#else/ ) {
				# invert ifdef
				$ifdef[ $#ifdef ] = undef;
			} elsif ( $line =~ /#endif/ ) {
				pop @ifdef;
			} elsif ( $line =~ /$sym/ ) {
				my $notbad = 0;
				foreach my $d ( grep defined, @ifdef ) {
					if ( $d eq $sym ) {
						$notbad = 1;
						last;
					}
				}
				$bad++ unless $notbad;
			}

		}
		if ( $bad ) {
			fail( "$sym symbol used badly $bad times in $file" );
		} else {
			pass( "$sym symbol used correctly in $file" );
		}

	}
}

__END__
cmp_ok( scalar ( @check ), '>=', 300, 'at least 300 symbols' );

foreach my $sym ( @check ) {
	my $value;
	eval "\$value = $sym();";
	is( $@, "", "$sym constant can be retrieved" );
	ok( defined( $value ), "$sym is defined");
	like( $value, qr/^-?\d+$/, "$sym value is an integer" );
}

{
	my $value;
	eval { $value = LIBCURL_COPYRIGHT() };
	is( $@, "", 'LIBCURL_COPYRIGHT constant can be retrieved' );
	ok( defined( $value ), "LIBCURL_COPYRIGHT is defined");
	like( $value, qr/[a-z]/i, 'LIBCURL_COPYRIGHT is a string' );
}
{
	my $value;
	eval { $value = LIBCURL_TIMESTAMP() };
	is( $@, "", 'LIBCURL_TIMESTAMP constant can be retrieved' );
	ok( defined( $value ), "LIBCURL_TIMESTAMP is defined");
	like( $value, qr/[a-z]/i, 'LIBCURL_TIMESTAMP is a string' );
}
{
	my $value;
	eval { $value = LIBCURL_VERSION() };
	is( $@, "", 'LIBCURL_VERSION constant can be retrieved' );
	ok( defined( $value ), "LIBCURL_VERSION is defined");
	like( $value, qr/^7\.\d{2}\.\d{1,2}(-.*)?$/, 'LIBCURL_VERSION is correct' );
}
