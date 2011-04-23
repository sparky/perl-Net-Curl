package Test::UnConstant;
=head1 NAME

Test::UnConstant -- convert numeric value to constant name

=head1 SYNOPSIS

 use Test::UnConstant;

 my $value2name = Test::UnConstant::val(
     'My::Package', qr/CONSTANT_RE/
 );

 print $value2name->( $some_value );
 # prints CONSTANT_NAME ($some_value)

 my $value2or = Test::UnConstant::or(
     'My::Package', qr/CONSTANT_OR_RE/
 );

 print $value2or->( $somenum | $othernum );
 # prints CNT1_NAME ($somenum) | CNT2_NAME ($othernum)

=cut

use warnings;
use strict;
use Scalar::Util qw(dualvar);

sub _extract
{
	my ( $package, $regexp ) = @_;

	my @keys;
	{
		no strict 'refs';
		@keys = keys %{ $package . "::" };
	}
	my %c;
	foreach my $n ( grep /^(?:$regexp)/, @keys ) {
		my $val = eval join "::", $package, $n;
		if ( exists $c{ $val } ) {
			warn "$n: value $val already belongs to $c{ $val }\n";
		} else {
			$c{ $val } = $n;
		}
	}

	return \%c;
}

sub _value
{
	my ( $c, $val ) = @_;

	if ( exists $c->{ $val } ) {
		return "$c->{ $val } ($val)";
	} else {
		return "UNKNOWN CNT ($val)";
	}
}

sub _or
{
	my ( $c, $val ) = @_;

	$val = 0 | $val;
	if ( $val == 0 ) {
		return "$c->{ $val } ($val)" if exists $c->{ $val };
		return "ZERO (0)";
	}

	my @out;
	# check larger values first (ie: check b1100 before b1000)
	foreach my $v ( sort { $b <=> $a } keys %$c ) {
		next unless $v == ( $val & $v );
		$val &= ~$v;
		push @out, "$c->{ $v } ($v)";
	}
	# but it is more intuitive to read smaller first
	@out = reverse @out;
	if ( $val ) {
		push @out, "UNKNOWN CNT ($val)";
	}

	return join " | ", @out;
}

=head1 FUNCTIONS

None of those functions are exported.

=head2 val PACKAGE, REGEXP

Extracts constants matching REGEXP from package PACKAGE. Returns a sub that
will convert constant values to constant names.

=cut
sub val
{
	my $c = _extract( @_ );
	return sub { my $v = shift; return dualvar $v, _value( $c, $v ); };
}

=head2 or PACKAGE, REGEXP

Extracts constants matching REGEXP from package PACKAGE. Returns a sub that
will convert bitmask values to a list of constant names which form that mask.

=cut
sub or
{
	my $c = _extract( @_ );
	return sub { my $v = shift; return dualvar $v, _or( $c, $v ); };
}

=head1 BUGS

Should have better package name.

Could be more useful.

=head1 AUTHORS

Przemyslaw Iskra <sparky at pld-linux.org>.

=cut
1;
