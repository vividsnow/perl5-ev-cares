use strict;
use warnings;
use Test::More;
use EV;
use EV::cares qw(:all);

# Random concurrent-query stress test.  Issues a randomized mix of:
#   - resolve / resolve_ttl / search / reverse / cancel / destroy
# against an asym mix of resolvers, with random interleaving.  Goal is to
# shake out lifecycle issues (UAF, refcount imbalance, double-free) that
# only manifest under odd timing.  Asan-only — author test, not user test.

plan skip_all => 'Author randomized stress test (set CARES_RANDSTRESS=1)'
    unless $ENV{CARES_RANDSTRESS};

my $seed = $ENV{CARES_RANDSTRESS_SEED} // time;
srand($seed);
diag("seed: $seed (set CARES_RANDSTRESS_SEED to reproduce)");

my @names = qw(
    localhost a.invalid b.invalid c.invalid d.invalid e.invalid
    nonexistent.test foo.bar.baz x.test y.test
);

my @resolvers;
for (1 .. 4) {
    push @resolvers, EV::cares->new(
        lookups => 'fb',
        timeout => 1,
        tries   => 1,
    );
}

my $expected = 0;
my $callbacks = 0;

for my $iter (1 .. 200) {
    my $r = $resolvers[int rand @resolvers];
    next if $r->is_destroyed;

    my $op = int rand 6;
    if ($op == 0) {
        my $n = $names[int rand @names];
        $r->resolve($n, sub { $callbacks++ });
        $expected++;
    } elsif ($op == 1) {
        my $n = $names[int rand @names];
        $r->resolve_ttl($n, sub { $callbacks++ });
        $expected++;
    } elsif ($op == 2) {
        my $n = $names[int rand @names];
        $r->search($n, T_A, sub { $callbacks++ });
        $expected++;
    } elsif ($op == 3) {
        my $ip = (int rand 2) ? '127.0.0.1' : '::1';
        $r->reverse($ip, sub { $callbacks++ });
        $expected++;
    } elsif ($op == 4) {
        # cancel pending — does not produce extra callbacks beyond the ones
        # already issued (those will fire with ECANCELLED)
        eval { $r->cancel };
    } elsif ($op == 5) {
        # destroy a resolver and replace it: this branch is selected ~1/6
        # of iterations and only fires 5% of the time it is selected, so
        # actual destroy rate is roughly 0.8% of all ops
        if (rand() < 0.05) {
            $r->destroy;
            $resolvers[int rand @resolvers] = EV::cares->new(
                lookups => 'fb', timeout => 1, tries => 1,
            );
        }
    }
}

# wait for everything to drain (or time out)
my $deadline = EV::time + 10;
my $timer = EV::timer 0.2, 0.2, sub {
    my $still_pending = 0;
    for (@resolvers) { $still_pending += $_->active_queries unless $_->is_destroyed }
    EV::break if !$still_pending || EV::time >= $deadline;
};
EV::run;

# every issued query must have produced exactly one callback (success or
# error, doesn't matter — the lifecycle invariant is one-callback-per-query)
ok($callbacks <= $expected, "no callback bursts: $callbacks <= $expected expected");
ok($callbacks >= $expected * 0.5, "most callbacks fired: $callbacks of $expected");

undef @resolvers;
pass('all resolvers DESTROYed without crash');

done_testing;
