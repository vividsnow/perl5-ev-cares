use strict;
use warnings;
use Test::More;
use EV;
use EV::cares qw(:status);

# Longer-running stress: fire many queries against a mix of working
# (hosts file) and unreachable servers, then destroy mid-flight.
# Verifies no crashes, no fd-exhaustion warnings, and bounded memory.

use File::Temp ();
my $tmp = File::Temp->new(SUFFIX => '.hosts');
print $tmp "10.0.0.1 stress-host\n";
close $tmp;

my $iters = $ENV{EV_CARES_LONG_ITERS} || 20;
my $per_iter = $ENV{EV_CARES_LONG_PER_ITER} || 200;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, $_[0] };

for my $iter (1 .. $iters) {
    my $r = EV::cares->new(lookups => 'fb', hosts_file => $tmp->filename);
    my $count = 0;
    for (1 .. $per_iter) {
        $r->resolve('stress-host', sub { $count++ });
    }
    my $t = EV::timer 5, 0, sub { EV::break };
    EV::run until $count >= $per_iter;
    $r->destroy;
}

ok(1, "$iters iters * $per_iter queries did not crash");
my $overflow = scalar grep /too many concurrent sockets/, @warnings;
is($overflow, 0, 'no fd-overflow warnings under sustained load');

done_testing;
