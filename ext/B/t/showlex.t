#!./perl

BEGIN {
    chdir 't' if -d 't';
    if ($^O eq 'MacOS') {
	@INC = qw(: ::lib ::macos:lib);
    } else {
	@INC = '../lib';
    }
    require './test.pl';
}

$| = 1;
use warnings;
use strict;
use Config;
use B::Showlex ();

plan tests => 8;

my $verbose = @ARGV; # set if ANY ARGS

my $a;
my $Is_VMS = $^O eq 'VMS';
my $Is_MacOS = $^O eq 'MacOS';

my $path = join " ", map { qq["-I$_"] } @INC;
$path = '"-I../lib" "-Iperl_root:[lib]"' if $Is_VMS;   # gets too long otherwise
my $redir = $Is_MacOS ? "" : "2>&1";
my $is_thread = $Config{use5005threads} && $Config{use5005threads} eq 'define';

if ($is_thread) {
    ok "# use5005threads: test skipped\n";
} else {
    $a = `$^X $path "-MO=Showlex" -e "my \@one" $redir`;
    like ($a, qr/sv_undef.*PVNV.*\@one.*sv_undef.*AV/s,
	  "canonical usage works");
}

# v1.01 tests

my ($na,$nb,$nc); # holds regex-strs
sub padrep {
    my $varname = shift;
    return "PVNV \\\(0x[0-9a-fA-F]+\\\) \\$varname\n";
}

my $out = runperl ( switches => ["-MO=Showlex"], 
		   prog => 'my ($a,$b)', stderr => 1 );
$na = padrep('$a');
$nb = padrep('$b');
like ($out, qr/1: $na/ms, 'found $a in "my ($a,$b)"');
like ($out, qr/2: $nb/ms, 'found $b in "my ($a,$b)"');

print $out if $verbose;

our $buf = 'arb startval';
my $ak = B::Showlex::walk_output (\$buf);

my $walker = B::Showlex::compile(sub { my ($foo,$bar) });
$walker->();
$na = padrep('$foo');
$nb = padrep('$bar');
like ($buf, qr/1: $na/ms, 'found $foo in "sub { my ($foo,$bar) }"');
like ($buf, qr/2: $nb/ms, 'found $bar in "sub { my ($foo,$bar) }"');

print $buf if $verbose;

$ak = B::Showlex::walk_output (\$buf);

$walker = B::Showlex::compile(sub { my ($scalar,@arr,%hash) });
$walker->();
$na = padrep('$scalar');
$nb = padrep('@arr');
$nc = padrep('%hash');
like ($buf, qr/1: $na/ms, 'found $scalar in "sub { my ($scalar,@arr,%hash) }"');
like ($buf, qr/2: $nb/ms, 'found @arr    in "sub { my ($scalar,@arr,%hash) }"');
like ($buf, qr/3: $nc/ms, 'found %hash   in "sub { my ($scalar,@arr,%hash) }"');

print $buf if $verbose;

my $asub = sub {
    my ($self,%props)=@_;
    my $total;
    { # inner block vars
	my (@fib)=(1,2);
	for (my $i=2; $i<10; $i++) {
	    $fib[$i] = $fib[$i-2] + $fib[$i-1];
	}
	for my $i(0..10) {
	    $total += $i;
	}
    }
};
$walker = B::Showlex::compile($asub, '-newlex');
$walker->();

$walker = B::Concise::compile($asub, '-exec');
$walker->();


print $buf if $verbose;
