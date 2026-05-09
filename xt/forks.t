use strict;
use warnings;
use Test::More;
use POSIX ();
use EV;
use EV::cares qw(:status);

# c-ares channels are NOT documented as fork-safe: file descriptors,
# socket state, and timer state are duplicated between parent and child
# but they refer to the same kernel objects.  This test documents the
# expected workflow — each process must create its own resolver after
# fork — and verifies it works in practice.

plan skip_all => 'fork not supported on this platform'
    unless eval { POSIX::WIFEXITED(0); 1 };

# Pre-fork: parent creates a resolver, fires a hosts-file lookup
use File::Temp ();
my $tmp = File::Temp->new(SUFFIX => '.hosts');
print $tmp "10.1.1.1 parent-host\n10.2.2.2 child-host\n";
close $tmp;

my $r_parent = EV::cares->new(lookups => 'f', hosts_file => $tmp->filename);

my $pid = fork;
defined $pid or die "fork: $!";

if ($pid == 0) {
    # Child: pre-fork resolver is unsafe to use here.  The supported
    # workflow is to destroy it (release fds back into our own copy)
    # and create a fresh one on a fresh EV loop so we don't inherit
    # any of the parent's libev watcher state.
    $r_parent->destroy;
    my $loop = EV::Loop->new;
    my $r = EV::cares->new(loop => $loop, lookups => 'f',
                           hosts_file => $tmp->filename);
    my @got;
    my $done;
    $r->resolve('child-host', sub { @got = @_; $done = 1 });
    my $t = $loop->timer(5, 0, sub { $done = 1 });
    $loop->run until $done;
    my $ok = $got[0] == ARES_SUCCESS
          && grep { $_ eq '10.2.2.2' } @got[1..$#got];
    POSIX::_exit($ok ? 0 : 1);
}

# Parent: own resolver still works
my @got;
my $done;
$r_parent->resolve('parent-host', sub { @got = @_; $done = 1 });
my $t = EV::timer 5, 0, sub { $done = 1 };
EV::run until $done;

is($got[0], ARES_SUCCESS, 'parent resolver works after fork');
ok(grep({ $_ eq '10.1.1.1' } @got[1..$#got]),
   'parent gets parent-host -> 10.1.1.1');

waitpid $pid, 0;
my $rc = $? >> 8;
is($rc, 0, 'child resolver (fresh post-fork) works');

done_testing;
