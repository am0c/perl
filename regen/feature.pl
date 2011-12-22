#!/usr/bin/perl
# 
# Regenerate (overwriting only if changed):
#
#    lib/feature.pm
#    feature.h
#
# from information hardcoded into this script.
#
# This script is normally invoked from regen.pl.

BEGIN {
    require 'regen/regen_lib.pl';
    push @INC, './lib';
}
use strict ;

# (feature name) => (internal name, used in %^H)
my %feature = (
    say             => 'say',
    state           => 'state',
    switch          => 'switch',
    evalbytes       => 'evalbytes',
    current_sub     => '__SUB__',
    unicode_eval    => 'unieval',
    unicode_strings => 'unicode',
);

# These work backwards--the presence of the hint elem disables the feature:
my %default_feature = (
    array_base      => 'noarybase',
);

my %feature_bundle = (
     default =>	[keys %default_feature],
    "5.9.5"  =>	[qw(say state switch array_base)],
    "5.10"   =>	[qw(say state switch array_base)],
    "5.11"   =>	[qw(say state switch unicode_strings array_base)],
    "5.12"   =>	[qw(say state switch unicode_strings array_base)],
    "5.13"   =>	[qw(say state switch unicode_strings array_base)],
    "5.14"   =>	[qw(say state switch unicode_strings array_base)],
    "5.15"   =>	[qw(say state switch unicode_strings unicode_eval
		    evalbytes current_sub)],
    "5.16"   =>	[qw(say state switch unicode_strings unicode_eval
		    evalbytes current_sub)],
);

###########################################################################

my %UniqueBundles; # "say state switch" => 5.10
my %Aliases;       #  5.12 => 5.11
for( sort keys %feature_bundle ) {
    my $value = join(' ', sort @{$feature_bundle{$_}});
    if (exists $UniqueBundles{$value}) {
	$Aliases{$_} = $UniqueBundles{$value};
    }
    else {
	$UniqueBundles{$value} = $_;
    }
}

###########################################################################


my ($pm, $h) = map {
    open_new($_, '>', { by => 'regen/feature.pl' });
} 'lib/feature.pm', 'feature.h';


while (<DATA>) {
    last if /^FEATURES$/ ;
    print $pm $_ ;
}

sub longest {
    my $long;
    for(@_) {
	if (!defined $long or length $long < length) {
	    $long = $_;
	}
    }
    $long;
}

print $pm "my %feature = (\n";
my $width = length longest keys %feature;
for(sort { length $a <=> length $b } keys %feature) {
    print $pm "    $_" . " "x($width-length)
	    . " => 'feature_$feature{$_}',\n";
}
print $pm ");\n\n";

print $pm "my %default_feature = (\n";
$width = length longest keys %default_feature;
for(sort { length $a <=> length $b } keys %default_feature) {
    print $pm "    $_" . " "x($width-length)
	. " => 'feature_$default_feature{$_}',\n";
}
print $pm ");\n\n";

print $pm "our %feature_bundle = (\n";
$width = length longest values %UniqueBundles;
for( sort { $UniqueBundles{$a} cmp $UniqueBundles{$b} }
          keys %UniqueBundles ) {
    my $bund = $UniqueBundles{$_};
    print $pm qq'    "$bund"' . " "x($width-length $bund)
	    . qq' => [qw($_)],\n';
}
print $pm ");\n\n";

for (sort keys %Aliases) {
    print $pm
	qq'\$feature_bundle{"$_"} = \$feature_bundle{"$Aliases{$_}"};\n';
};


while (<DATA>) {
    print $pm $_ ;
}

read_only_bottom_close_and_rename($pm);

my $HintShift;

open "perl.h", "perl.h" or die "$0 cannot open perl.h: $!";
perlh: {
    while (readline "perl.h") {
	next unless /#define\s+HINT_FEATURE_MASK/;
	/(0x[A-Fa-f0-9]+)/ or die "No hex number in:\n\n$_\n ";
	my $hex = $1;
	my $bits = sprintf "%b", oct $1;
	$bits =~ /^0*1+(0*)\z/
	 or die "Non-contiguous bits in $bits (binary for $hex):\n\n$_\n ";
	$HintShift = length $1;
	my $bits_needed =
	    length sprintf "%b", scalar keys %UniqueBundles;
	$bits =~ /1{$bits_needed}/
	    or die "Not enough bits (need $bits_needed)"
		 . " in $bits (binary for $hex):\n\n$_\n";
	last perlh;
    }
    die "No HINT_FEATURE_MASK defined in perl.h";
}
close "perl.h";

my $first_bit = sprintf "0x%08x", 1 << $HintShift;
print $h <<EOH;

#if defined(PERL_CORE) || defined (PERL_EXT)

#define HINT_FEATURE_SHIFT	$HintShift

#define FEATURE_BUNDLE_DEFAULT	0
EOH

my $count;
for (sort values %UniqueBundles) {
    (my $key = $_) =~ y/.//d;
    next if $key =~ /\D/;
    print $h "#define FEATURE_BUNDLE_$key	", ++$count, "\n";
}

print $h <<EOH;
#define FEATURE_BUNDLE_CUSTOM	(HINT_FEATURE_MASK >> HINT_FEATURE_SHIFT)

#define CURRENT_HINTS \\
    (PL_curcop == &PL_compiling ? PL_hints : PL_curcop->cop_hints)
#define CURRENT_FEATURE_BUNDLE	(CURRENT_HINTS >> HINT_FEATURE_SHIFT)

#endif /* PERL_CORE or PERL_EXT */
EOH

read_only_bottom_close_and_rename($h);

__END__
package feature;

our $VERSION = '1.25';

FEATURES

# This gets set (for now) in $^H as well as in %^H,
# for runtime speed of the uc/lc/ucfirst/lcfirst functions.
# See HINT_UNI_8_BIT in perl.h.
our $hint_uni8bit = 0x00000800;

# TODO:
# - think about versioned features (use feature switch => 2)

=head1 NAME

feature - Perl pragma to enable new features

=head1 SYNOPSIS

    use feature qw(say switch);
    given ($foo) {
        when (1)          { say "\$foo == 1" }
        when ([2,3])      { say "\$foo == 2 || \$foo == 3" }
        when (/^a[bc]d$/) { say "\$foo eq 'abd' || \$foo eq 'acd'" }
        when ($_ > 100)   { say "\$foo > 100" }
        default           { say "None of the above" }
    }

    use feature ':5.10'; # loads all features available in perl 5.10

    use v5.10;           # implicitly loads :5.10 feature bundle

=head1 DESCRIPTION

It is usually impossible to add new syntax to Perl without breaking
some existing programs.  This pragma provides a way to minimize that
risk. New syntactic constructs, or new semantic meanings to older
constructs, can be enabled by C<use feature 'foo'>, and will be parsed
only when the appropriate feature pragma is in scope.  (Nevertheless, the
C<CORE::> prefix provides access to all Perl keywords, regardless of this
pragma.)

=head2 Lexical effect

Like other pragmas (C<use strict>, for example), features have a lexical
effect. C<use feature qw(foo)> will only make the feature "foo" available
from that point to the end of the enclosing block.

    {
        use feature 'say';
        say "say is available here";
    }
    print "But not here.\n";

=head2 C<no feature>

Features can also be turned off by using C<no feature "foo">.  This too
has lexical effect.

    use feature 'say';
    say "say is available here";
    {
        no feature 'say';
        print "But not here.\n";
    }
    say "Yet it is here.";

C<no feature> with no features specified will turn off all features.

=head1 AVAILABLE FEATURES

=head2 The 'say' feature

C<use feature 'say'> tells the compiler to enable the Perl 6 style
C<say> function.

See L<perlfunc/say> for details.

This feature is available starting with Perl 5.10.

=head2 The 'state' feature

C<use feature 'state'> tells the compiler to enable C<state>
variables.

See L<perlsub/"Persistent Private Variables"> for details.

This feature is available starting with Perl 5.10.

=head2 The 'switch' feature

C<use feature 'switch'> tells the compiler to enable the Perl 6
given/when construct.

See L<perlsyn/"Switch statements"> for details.

This feature is available starting with Perl 5.10.

=head2 The 'unicode_strings' feature

C<use feature 'unicode_strings'> tells the compiler to use Unicode semantics
in all string operations executed within its scope (unless they are also
within the scope of either C<use locale> or C<use bytes>).  The same applies
to all regular expressions compiled within the scope, even if executed outside
it.

C<no feature 'unicode_strings'> tells the compiler to use the traditional
Perl semantics wherein the native character set semantics is used unless it is
clear to Perl that Unicode is desired.  This can lead to some surprises
when the behavior suddenly changes.  (See
L<perlunicode/The "Unicode Bug"> for details.)  For this reason, if you are
potentially using Unicode in your program, the
C<use feature 'unicode_strings'> subpragma is B<strongly> recommended.

This feature is available starting with Perl 5.12, but was not fully
implemented until Perl 5.14.

=head2 The 'unicode_eval' and 'evalbytes' features

Under the C<unicode_eval> feature, Perl's C<eval> function, when passed a
string, will evaluate it as a string of characters, ignoring any
C<use utf8> declarations.  C<use utf8> exists to declare the encoding of
the script, which only makes sense for a stream of bytes, not a string of
characters.  Source filters are forbidden, as they also really only make
sense on strings of bytes.  Any attempt to activate a source filter will
result in an error.

The C<evalbytes> feature enables the C<evalbytes> keyword, which evaluates
the argument passed to it as a string of bytes.  It dies if the string
contains any characters outside the 8-bit range.  Source filters work
within C<evalbytes>: they apply to the contents of the string being
evaluated.

Together, these two features are intended to replace the historical C<eval>
function, which has (at least) two bugs in it, that cannot easily be fixed
without breaking existing programs:

=over

=item *

C<eval> behaves differently depending on the internal encoding of the
string, sometimes treating its argument as a string of bytes, and sometimes
as a string of characters.

=item *

Source filters activated within C<eval> leak out into whichever I<file>
scope is currently being compiled.  To give an example with the CPAN module
L<Semi::Semicolons>:

    BEGIN { eval "use Semi::Semicolons;  # not filtered here " }
    # filtered here!

C<evalbytes> fixes that to work the way one would expect:

    use feature "evalbytes";
    BEGIN { evalbytes "use Semi::Semicolons;  # filtered " }
    # not filtered

=back

These two features are available starting with Perl 5.16.

=head2 The 'current_sub' feature

This provides the C<__SUB__> token that returns a reference to the current
subroutine or C<undef> outside of a subroutine.

This feature is available starting with Perl 5.16.

=head2 The 'array_base' feature

This feature supports the legacy C<$[> variable.  See L<perlvar/$[> and
L<arybase>.  It is on by default but disabled under C<use v5.16> (see
L</IMPLICIT LOADING>, below).

This feature is available under this name starting with Perl 5.16.  In
previous versions, it was simply on all the time, and this pragma knew
nothing about it.

=head1 FEATURE BUNDLES

It's possible to load multiple features together, using
a I<feature bundle>.  The name of a feature bundle is prefixed with
a colon, to distinguish it from an actual feature.

  use feature ":5.10";

The following feature bundles are available:

  bundle    features included
  --------- -----------------
  :default  array_base

  :5.10     say state switch array_base

  :5.12     say state switch unicode_strings array_base

  :5.14     say state switch unicode_strings array_base

  :5.16     say state switch unicode_strings
            unicode_eval evalbytes current_sub

The C<:default> bundle represents the feature set that is enabled before
any C<use feature> or C<no feature> declaration.

Specifying sub-versions such as the C<0> in C<5.14.0> in feature bundles has
no effect.  Feature bundles are guaranteed to be the same for all sub-versions.

  use feature ":5.14.0";    # same as ":5.14"
  use feature ":5.14.1";    # same as ":5.14"

=head1 IMPLICIT LOADING

Instead of loading feature bundles by name, it is easier to let Perl do
implicit loading of a feature bundle for you.

There are two ways to load the C<feature> pragma implicitly:

=over 4

=item *

By using the C<-E> switch on the Perl command-line instead of C<-e>.
That will enable the feature bundle for that version of Perl in the
main compilation unit (that is, the one-liner that follows C<-E>).

=item *

By explicitly requiring a minimum Perl version number for your program, with
the C<use VERSION> construct.  That is,

    use v5.10.0;

will do an implicit

    no feature;
    use feature ':5.10';

and so on.  Note how the trailing sub-version
is automatically stripped from the
version.

But to avoid portability warnings (see L<perlfunc/use>), you may prefer:

    use 5.010;

with the same effect.

If the required version is older than Perl 5.10, the ":default" feature
bundle is automatically loaded instead.

=back

=cut

sub import {
    my $class = shift;
    if (@_ == 0) {
        croak("No features specified");
    }
    while (@_) {
        my $name = shift(@_);
        if (substr($name, 0, 1) eq ":") {
            my $v = substr($name, 1);
            if (!exists $feature_bundle{$v}) {
                $v =~ s/^([0-9]+)\.([0-9]+).[0-9]+$/$1.$2/;
                if (!exists $feature_bundle{$v}) {
                    unknown_feature_bundle(substr($name, 1));
                }
            }
            unshift @_, @{$feature_bundle{$v}};
            next;
        }
        if (!exists $feature{$name}) {
	  if (!exists $default_feature{$name}) {
            unknown_feature($name);
	  }
	  delete $^H{$default_feature{$name}}; next;
        }
        $^H{$feature{$name}} = 1;
        $^H |= $hint_uni8bit if $name eq 'unicode_strings';
    }
}

sub unimport {
    my $class = shift;

    # A bare C<no feature> should disable *all* features
    if (!@_) {
        delete @^H{ values(%feature) };
        $^H &= ~ $hint_uni8bit;
	@^H{ values(%default_feature) } = (1) x keys %default_feature;
        return;
    }

    while (@_) {
        my $name = shift;
        if (substr($name, 0, 1) eq ":") {
            my $v = substr($name, 1);
            if (!exists $feature_bundle{$v}) {
                $v =~ s/^([0-9]+)\.([0-9]+).[0-9]+$/$1.$2/;
                if (!exists $feature_bundle{$v}) {
                    unknown_feature_bundle(substr($name, 1));
                }
            }
            unshift @_, @{$feature_bundle{$v}};
            next;
        }
        if (!exists($feature{$name})) {
	  if (!exists $default_feature{$name}) {
            unknown_feature($name);
	  }
	  $^H{$default_feature{$name}} = 1; next;
        }
        else {
            delete $^H{$feature{$name}};
            $^H &= ~ $hint_uni8bit if $name eq 'unicode_strings';
        }
    }
}

sub unknown_feature {
    my $feature = shift;
    croak(sprintf('Feature "%s" is not supported by Perl %vd',
            $feature, $^V));
}

sub unknown_feature_bundle {
    my $feature = shift;
    croak(sprintf('Feature bundle "%s" is not supported by Perl %vd',
            $feature, $^V));
}

sub croak {
    require Carp;
    Carp::croak(@_);
}

1;
