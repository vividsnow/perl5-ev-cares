use strict;
use warnings;
use Test::More;
use File::Temp ();

plan skip_all => 'valgrind not in PATH'
    unless `which valgrind 2>/dev/null` =~ /valgrind/;

# memory errors only (UAF/double free/invalid access): no --leak-check,
# its non-debug-perl exit noise is useless here -- leaks are xt/leak.t's job

my %scenario = (
    'basic resolve + destroy' => <<'PERL',
use EV;
use EV::cares qw(:status);
my $r = EV::cares->new(lookups => 'f');
my $done;
$r->resolve('localhost', sub { $done = 1 });
my $t = EV::timer 5, 0, sub { $done = 1 };
EV::run until $done;
$r->destroy;
PERL
    'last ref dropped in-callback with queries pending' => <<'PERL',
use EV;
use EV::cares qw(:status);
my $r = EV::cares->new(servers => '192.0.2.1', timeout => 1, tries => 1);
$r->resolve('p1.blackhole.example.com', sub { });
$r->resolve('p2.blackhole.example.com', sub { });
my $done;
$r->resolve('localhost', sub { undef $r; $done = 1 });
my $t = EV::timer 5, 0, sub { $done = 1 };
EV::run until $done;
PERL
);

for my $name (sort keys %scenario) {
    my $tmp = File::Temp->new(SUFFIX => '.pl');
    print $tmp $scenario{$name};
    close $tmp;

    my $cmd = sprintf
        'valgrind --error-exitcode=99 %s -Mblib -- %s 2>&1',
        $^X, $tmp->filename;

    my $out = `$cmd`;
    my $rc  = $? >> 8;

    is($rc, 0, "valgrind reports no errors ($name)")
        or diag $out;
}

done_testing;
