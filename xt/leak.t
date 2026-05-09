use strict;
use warnings;
use Test::More;
plan skip_all => 'Test::LeakTrace required'
    unless eval 'use Test::LeakTrace; 1';

use EV;
use EV::cares qw(:status);

no_leaks_ok(sub {
    for (1..5) {
        my $r = EV::cares->new(lookups => 'f');
        my $done;
        $r->resolve('localhost', sub { $done = 1 });
        my $t = EV::timer 5, 0, sub { $done = 1 };
        EV::run until $done;
    }
}, 'create/resolve/destroy cycle does not leak');

no_leaks_ok(sub {
    my $r = EV::cares->new(lookups => 'f');
    my $count = 0;
    for (1..20) {
        $r->resolve('localhost', sub { $count++ });
    }
    my $t = EV::timer 5, 0, sub { EV::break };
    EV::run until $count >= 20;
}, 'fan-out queries on shared resolver does not leak');

done_testing;
