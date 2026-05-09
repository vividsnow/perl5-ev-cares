use strict;
use warnings;
use Test::More;
use File::Temp ();
use Config;

plan skip_all => 'valgrind not in PATH'
    unless `which valgrind 2>/dev/null` =~ /valgrind/;

plan skip_all => 'valgrind on a non-debug perl is too noisy'
    unless $Config{usedebugging} || $ENV{EV_CARES_VALGRIND_FORCE};

my $script = <<'PERL';
use EV;
use EV::cares qw(:status);
my $r = EV::cares->new(lookups => 'f');
my $done;
$r->resolve('localhost', sub { $done = 1 });
my $t = EV::timer 5, 0, sub { $done = 1 };
EV::run until $done;
$r->destroy;
PERL

my $tmp = File::Temp->new(SUFFIX => '.pl');
print $tmp $script;
close $tmp;

my $cmd = sprintf
    'valgrind --error-exitcode=99 --leak-check=full %s -Mblib -- %s 2>&1',
    $^X, $tmp->filename;

my $out = `$cmd`;
my $rc  = $? >> 8;

is($rc, 0, 'valgrind reports no errors')
    or diag $out;

done_testing;
