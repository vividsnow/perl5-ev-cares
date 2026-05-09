use strict;
use warnings;
use Test::More;
use EV;
use EV::cares qw(:all);

# Random destroy timing across many in-flight queries.
# Catches UAF in the in_callback / free_pending path.

srand($ENV{STRESS_SEED} || 0xCA7E);

for my $iter (1 .. 20) {
    my $r = EV::cares->new(
        servers => ['127.0.0.1:9'],
        timeout => 1,
        tries   => 1,
    );

    for (1 .. 50) {
        $r->resolve("h$_-iter$iter.invalid.", sub { });
    }

    my $delay = rand(0.05);
    my $t = EV::timer $delay, 0, sub {
        eval { $r->destroy };
        EV::break;
    };
    EV::run;
    pass("iter $iter: destroyed after ${\ sprintf '%.3f', $delay}s without crash");
}

# Drop the last strong reference from inside a callback — verifies that
# the deferred-Safefree path (free_pending) handles closure-driven destroy.
{
    my $r = EV::cares->new(lookups => 'f');
    my $done;
    my $inner_ref = $r;     # captured by the closure below; keeps $r alive past undef
    $r->resolve('localhost', sub {
        undef $inner_ref;   # closure drops its capture inside the callback
        $done = 1;
    });
    undef $r;               # outer ref gone; the closure's capture is the only live ref
    my $t = EV::timer 5, 0, sub { $done = 1 };
    EV::run until $done;
    pass('drop-last-ref-from-callback survives');
}

done_testing;
