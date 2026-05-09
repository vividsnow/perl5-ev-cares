use strict;
use warnings;
use Test::More;
use Time::HiRes ();
use File::Temp ();
use EV;
use EV::cares qw(:status);

# Micro-benchmark: how many local-only resolves per second can we sustain
# from a single channel? Records the rate as a diag for tracking trends;
# fails only if we drop below an aggressively-low floor (catches a
# major regression, not normal jitter).

my $tmp = File::Temp->new(SUFFIX => '.hosts');
print $tmp "10.0.0.1 perf-host\n";
close $tmp;

my $r = EV::cares->new(lookups => 'fb', hosts_file => $tmp->filename);
my $count = 0;
my $target = $ENV{EV_CARES_PERF_N} || 1000;

my $t0 = Time::HiRes::time();
for (1 .. $target) {
    $r->resolve('perf-host', sub { $count++ });
}
my $timer = EV::timer 30, 0, sub { EV::break };
EV::run until $count >= $target;
my $elapsed = Time::HiRes::time() - $t0;

diag sprintf "resolved %d local hostnames in %.3fs (%d/s)",
    $count, $elapsed, $count / ($elapsed || 1);

is($count, $target, "all $target queries completed");
my $rate = $count / ($elapsed || 1);
my $floor = $ENV{EV_CARES_PERF_FLOOR} || 100;
cmp_ok($rate, '>=', $floor,
    "throughput >= $floor/s (got " . int($rate) . "/s)");

done_testing;
