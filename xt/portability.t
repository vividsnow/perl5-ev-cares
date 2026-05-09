use strict;
use warnings;
use Test::More;
use Socket qw(AF_INET AF_INET6);
use EV::cares;

# Diagnose platform-dependent constants relied on by the XS code.
# Catches regressions of the kind we hit during 0.02 development:
# `getnameinfo` family-offset differs between Linux/glibc (sa_family_t
# = u_int16, offset 0) and BSD/macOS (sa_family_t = u_int8, offset 1).

# AF_* values are platform-specific but EV::cares' BOOT registers them
# from system headers, so they should match Socket's values.
is(EV::cares::AF_INET(),  AF_INET,  'AF_INET matches Socket');
is(EV::cares::AF_INET6(), AF_INET6, 'AF_INET6 matches Socket');

# sa_family_t width: pack 'S' (short, 2 bytes) is the Linux layout.
# On BSD-derived systems sa_len occupies the first byte and sa_family
# is at offset 1, so a 1-byte buffer like "x" cannot safely have its
# sa_family read.  Verify our XS getnameinfo length-check is robust.
my $sockaddr_min = length(pack('S', 0)) + 14;   # generic struct sockaddr is >= 16
diag sprintf "sa_family_t pack-width: %d byte(s) on %s",
    length(pack('S', 0)), $^O;
diag sprintf "INET6 addrstrlen heuristic: 46 (room for full IPv6 + scope)";

# Confirm the XS rejects too-short sockaddrs before reading sa_family.
{
    my $r = EV::cares::->new;
    eval { $r->getnameinfo("x", 0, sub {}) };
    like($@, qr/too short/, 'short sockaddr rejected on this platform');
}

# Endianness diagnostic
my $hex = unpack 'H*', pack('S', 1);
diag "byte order: pack('S',1) = 0x$hex (LE => '0100', BE => '0001')";

# Perl integer width
diag sprintf 'perl IV width: %d bits', 8 * length(pack('j', 0));

done_testing;
