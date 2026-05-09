use strict;
use warnings;
use Test::More;
use EV;
use EV::cares qw(:all);

# Reproducer for the global-destruction SEGV that previously hit Alpine/musl
# at process exit: a resolver with pending queries, IO watchers active in
# libev, and the EV::Loop dropped before EV::cares.  The lifecycle code in
# DESTROY guards this with a PL_dirty branch that intentionally leaks self
# rather than touching libev (which has unspecified teardown ordering).
#
# The real failure mode only manifests on musl + Alpine; on glibc the same
# code paths happen to be safe.  This test exercises the path on every
# platform so a refactor that breaks the PL_dirty guard is caught locally
# rather than only in CI.

# Run as a separate child process to capture exit status / signals cleanly.
my $child_script = <<'PERL';
use strict;
use warnings;
use EV;
use EV::cares qw(:all);

my $r = EV::cares->new(
    timeout => 1,
    tries   => 1,
    servers => ['127.0.0.255'],   # unreachable — keeps queries pending
);

# issue several queries that will never complete in this lifetime
for my $i (1 .. 5) {
    $r->resolve("pending-$i.invalid", sub { });
}

# do NOT call destroy.  Let global destruction tear everything down.
# The order is unspecified — this is exactly the path that triggered the
# original SEGV before the PL_dirty guard.  Successful teardown here means
# our DESTROY handler took the "leak self, don't touch libev" branch.

# return immediately — process exits with everything still pending
exit 0;
PERL

require File::Temp;
my $script = File::Temp->new(SUFFIX => '.pl');
print $script $child_script;
close $script;

my @perl = ($^X, '-Iblib/lib', '-Iblib/arch', "$script");
system @perl;
my $rc = $?;

is($rc, 0, "process exits cleanly with pending queries (rc=$rc)")
    or diag(sprintf "wstat=%d signal=%d core=%d",
                    $rc, $rc & 127, $rc & 128 ? 1 : 0);

done_testing;
