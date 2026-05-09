use strict;
use warnings;
use Test::More;
use EV::cares;

# Informational: report which optional c-ares features the module
# detected at build time. Always passes — the diag output is what
# matters when triaging a CPAN-tester report.

diag "c-ares lib_version: " . EV::cares::lib_version();

my %features = (
    'HTTPS/SVCB record parsing'   => defined &EV::cares::T_HTTPS,
    'qcache option'                => 1,  # always-compiled-in via #ifdef on the option
    'rotate option'                => 1,
    'set_sortlist'                 => defined &EV::cares::set_sortlist,
    'last_query_timeouts'          => defined &EV::cares::last_query_timeouts,
    'resolve_ttl'                  => defined &EV::cares::resolve_ttl,
    'search_all helper'            => defined &EV::cares::search_all,
    'resolve_all helper'           => defined &EV::cares::resolve_all,
);

for my $feat (sort keys %features) {
    diag sprintf "  %-32s %s", $feat, $features{$feat} ? 'YES' : 'no';
}

# Test 1: lib_version returns a sensible version string
like(EV::cares::lib_version(), qr/^\d+\.\d+\.\d+/,
    'lib_version returns dotted-decimal version');

# Test 2: T_HTTPS / T_SVCB available unconditionally (we shim them)
ok(defined &EV::cares::T_HTTPS, 'T_HTTPS exported');
ok(defined &EV::cares::T_SVCB,  'T_SVCB exported');

done_testing;
