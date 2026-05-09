use strict;
use warnings;
use Test::More;
use EV;
use EV::cares qw(:all);

# Author test: AF_INET6-only resolution.  Verifies that the v6-only hint
# path is honored across getaddrinfo / resolve / search and doesn't crash
# on hosts that lack v6 connectivity (typical CI environments).  We assert
# behavior, not v6 connectivity itself.

my $r = EV::cares->new(timeout => 5, tries => 2);

# resolve() with default family follows c-ares lookup behavior; we assert
# at least the call structure works and any returned addrs are v6.
{
    my ($status, @addrs);
    my $done;
    $r->getaddrinfo('localhost', undef, { family => AF_INET6 },
        sub { ($status, @addrs) = @_; $done = 1 });
    my $t = EV::timer 5, 0, sub { $done = 1 };
    EV::run until $done;
    ok(defined $status, 'getaddrinfo AF_INET6 returned a status');
    if ($status == ARES_SUCCESS) {
        my $v4 = grep { /^\d+\.\d+\.\d+\.\d+\z/ } @addrs;
        is($v4, 0, 'AF_INET6 hint returned no IPv4 addresses');
    } else {
        diag 'localhost has no IPv6 -- skipping addr-family assertion';
    }
}

# search() T_AAAA for a domain that always has IPv6
{
    my ($status, @addrs);
    my $done;
    $r->search('ipv6.google.com', T_AAAA, sub {
        ($status, @addrs) = @_;
        $done = 1;
    });
    my $t = EV::timer 10, 0, sub { $done = 1 };
    EV::run until $done;
    SKIP: {
        skip 'AAAA ipv6.google.com unavailable', 2
            unless defined $status && $status == ARES_SUCCESS;
        ok(@addrs > 0, 'AAAA returned at least one IPv6 address');
        like($addrs[0], qr/:/, 'AAAA result contains a colon (IPv6 form)');
    }
}

# reverse() of an IPv6 address goes through the v6 PTR path
{
    my ($status, @hosts);
    my $done;
    $r->reverse('::1', sub {
        ($status, @hosts) = @_;
        $done = 1;
    });
    my $t = EV::timer 5, 0, sub { $done = 1 };
    EV::run until $done;
    ok(defined $status, 'reverse(::1) returned a status');
    # PTR for ::1 may or may not exist; just verify the call structure
}

done_testing;
