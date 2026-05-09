use strict;
use warnings;
use Test::More;
use EV;
use EV::cares qw(:all);

# Author test: exercise the SVCB/HTTPS/TXT parsers on real responses with
# many records, long ALPN lists, or long TXT chunks.  Network-gated.

my $r = EV::cares->new(timeout => 5, tries => 2);
my $can_resolve;
$r->resolve('google.com', sub { $can_resolve = 1 if $_[0] == ARES_SUCCESS });
my $t0 = EV::timer 6, 0, sub { EV::break };
EV::run;
plan skip_all => 'no network connectivity' unless $can_resolve;

sub query {
    my ($name, $type) = @_;
    my @result;
    my $done;
    $r->search($name, $type, sub { @result = @_; $done = 1 });
    my $t = EV::timer 10, 0, sub { $done = 1 };
    EV::run until $done;
    return @result;
}

# Domains with many MX records exercise the per-record allocation path
# and the array growth in cares.xs:search_cb T_MX.
for my $domain ('google.com', 'microsoft.com', 'apple.com') {
    my ($status, @recs) = query($domain, T_MX);
    SKIP: {
        skip "MX $domain unavailable: " . EV::cares::strerror($status), 2
            if $status != ARES_SUCCESS;
        ok(@recs >= 1, "$domain MX returned >= 1 record (got " . @recs . ")");
        ok((scalar grep { ref($_) eq 'HASH' && exists $_->{host} } @recs)
                == scalar @recs,
            "all $domain MX records are well-formed hashrefs");
    }
}

# HTTPS records on cloudflare.com / google.com exercise the SVCB parser,
# including ALPN with multiple protocols and IPv4/IPv6 hints.
for my $domain ('cloudflare.com', 'google.com') {
    my ($status, @recs) = query($domain, T_HTTPS);
    SKIP: {
        skip "HTTPS $domain unavailable: " . EV::cares::strerror($status), 2
            if $status != ARES_SUCCESS;
        ok(@recs > 0, "$domain HTTPS returned at least one record");
        my $alpn_seen;
        for my $rr (grep { ref($_) eq 'HASH' } @recs) {
            if (exists $rr->{params}{alpn}) {
                ok(ref $rr->{params}{alpn} eq 'ARRAY',
                    "$domain HTTPS alpn is arrayref");
                $alpn_seen = 1;
                last;
            }
        }
        # if no ALPN, account for the second test we promised in skip(2)
        pass("$domain HTTPS has no alpn param (skipped detail check)")
            unless $alpn_seen;
    }
}

# TXT records often span multiple 255-byte chunks per record; google.com
# has SPF with concatenation.
{
    my ($status, @recs) = query('google.com', T_TXT);
    SKIP: {
        skip "TXT google.com unavailable: " . EV::cares::strerror($status), 2
            if $status != ARES_SUCCESS;
        ok(@recs > 0, 'TXT google.com returned records');
        ok((scalar grep { length($_) > 0 } @recs) == scalar @recs,
            'all TXT records are non-empty strings');
    }
}

done_testing;
