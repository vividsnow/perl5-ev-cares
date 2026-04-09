package EV::cares;
use strict;
use warnings;
use EV;

BEGIN {
    our $VERSION = '0.01';
    use XSLoader;
    XSLoader::load __PACKAGE__, $VERSION;
}

use Exporter 'import';

our @EXPORT_OK;
our %EXPORT_TAGS;

$EXPORT_TAGS{status} = [qw(
    ARES_SUCCESS ARES_ENODATA ARES_EFORMERR ARES_ESERVFAIL ARES_ENOTFOUND
    ARES_ENOTIMP ARES_EREFUSED ARES_EBADQUERY ARES_EBADNAME ARES_EBADFAMILY
    ARES_EBADRESP ARES_ECONNREFUSED ARES_ETIMEOUT ARES_EOF ARES_EFILE
    ARES_ENOMEM ARES_EDESTRUCTION ARES_EBADSTR ARES_EBADFLAGS ARES_ENONAME
    ARES_EBADHINTS ARES_ENOTINITIALIZED ARES_ECANCELLED ARES_ESERVICE
    ARES_ENOSERVER
)];

$EXPORT_TAGS{types} = [qw(
    T_A T_NS T_CNAME T_SOA T_PTR T_MX T_TXT T_AAAA T_SRV T_NAPTR T_CAA T_ANY
)];

$EXPORT_TAGS{classes} = [qw(C_IN C_CHAOS C_HS C_ANY)];

$EXPORT_TAGS{flags} = [qw(
    ARES_FLAG_USEVC ARES_FLAG_PRIMARY ARES_FLAG_IGNTC ARES_FLAG_NORECURSE
    ARES_FLAG_STAYOPEN ARES_FLAG_NOSEARCH ARES_FLAG_NOALIASES ARES_FLAG_NOCHECKRESP
    ARES_FLAG_EDNS ARES_FLAG_NO_DFLT_SVR ARES_FLAG_DNS0x20
)];

$EXPORT_TAGS{ai} = [qw(
    ARES_AI_CANONNAME ARES_AI_NUMERICHOST ARES_AI_PASSIVE ARES_AI_NUMERICSERV
    ARES_AI_V4MAPPED ARES_AI_ALL ARES_AI_ADDRCONFIG ARES_AI_NOSORT
)];

$EXPORT_TAGS{ni} = [qw(
    ARES_NI_NOFQDN ARES_NI_NUMERICHOST ARES_NI_NAMEREQD ARES_NI_NUMERICSERV
    ARES_NI_DGRAM ARES_NI_TCP ARES_NI_UDP
)];

$EXPORT_TAGS{families} = [qw(AF_INET AF_INET6 AF_UNSPEC)];

{
    my %seen;
    @EXPORT_OK = grep { !$seen{$_}++ } map { @$_ } values %EXPORT_TAGS;
    $EXPORT_TAGS{all} = [@EXPORT_OK];
}

1;

__END__

=head1 NAME

EV::cares - high-performance async DNS resolver using c-ares and EV

=head1 SYNOPSIS

    use EV;
    use EV::cares qw(:status :types);

    my $r = EV::cares->new(
        servers => ['8.8.8.8', '1.1.1.1'],
        timeout => 5,
        tries   => 3,
    );

    # simple resolve (A + AAAA)
    $r->resolve('example.com', sub {
        my ($status, @addrs) = @_;
        if ($status == ARES_SUCCESS) {
            print "resolved: @addrs\n";
        } else {
            warn "failed: " . EV::cares::strerror($status);
        }
    });

    # parsed DNS search
    $r->search('example.com', T_MX, sub {
        my ($status, @mx) = @_;
        for (@mx) {
            printf "MX %d %s\n", $_->{priority}, $_->{host};
        }
    });

    # raw query
    $r->query('example.com', C_IN, T_A, sub {
        my ($status, $buf) = @_;
        # $buf is the raw DNS response packet
    });

    EV::run;

=head1 DESCRIPTION

EV::cares integrates the c-ares asynchronous DNS library directly with
the EV event loop at the C level.  All socket management and timer
handling is done in XS -- zero Perl-level event processing overhead.

Multiple queries run concurrently; c-ares handles server rotation,
retries, and search-domain appending internally.

=head1 CONSTRUCTOR

=head2 new

    my $r = EV::cares->new(%opts);

Creates a new resolver.  All options are optional.

=over

=item servers => \@addrs | "addr1,addr2,..."

DNS server addresses.  Default: system resolv.conf servers.

=item timeout => $seconds

Per-try timeout (fractional seconds).  Default: 2s.

=item maxtimeout => $seconds

Maximum total timeout across all tries.

=item tries => $n

Number of query attempts.  Default: 2.

=item ndots => $n

Threshold for treating a name as "absolute" (no search suffix).
Default: 1.

=item flags => $flags

Channel flags (C<ARES_FLAG_*>), e.g. C<ARES_FLAG_EDNS | ARES_FLAG_USEVC>.

=item lookups => $string

Lookup order: C<"b"> = DNS, C<"f"> = /etc/hosts.  Default: C<"bf">.

=item rotate => 1

Round-robin among servers.

=item tcp_port => $port

=item udp_port => $port

Non-standard DNS port.

=item ednspsz => $bytes

EDNS0 UDP payload size.

=item resolvconf => $path

Custom resolv.conf path.

=item hosts_file => $path

Custom hosts file path.

=item udp_max_queries => $n

Max queries per UDP connection before reconnect.

=item qcache => $max_ttl

Enable query result cache with given max TTL (seconds).  0 = disabled.

=back

=head1 METHODS

=head2 resolve($name, $cb)

High-level resolver using C<ares_getaddrinfo> with C<AF_UNSPEC>.
Returns both IPv4 and IPv6 addresses.
Callback: C<($status, @ip_strings)>.

=head2 getaddrinfo($node, $service, \%hints, $cb)

Full C<getaddrinfo>.  C<$service> and C<\%hints> may be C<undef>.
Hint keys: C<family>, C<socktype>, C<protocol>, C<flags> (C<ARES_AI_*>).
Callback: C<($status, @ip_strings)>.

=head2 search($name, $type, $cb)

DNS search using search domains from resolv.conf.  Uses C<C_IN> class.
Results are auto-parsed based on C<$type>:

    T_A, T_AAAA  => ($status, @ip_strings)
    T_MX         => ($status, @{ {priority, host} })
    T_SRV        => ($status, @{ {priority, weight, port, target} })
    T_TXT        => ($status, @strings)
    T_NS         => ($status, @hostnames)
    T_SOA        => ($status, {mname, rname, serial, refresh, retry, expire, minttl})
    T_PTR        => ($status, @hostnames)
    T_NAPTR      => ($status, @{ {order, preference, flags, service, regexp, replacement} })
    T_CAA        => ($status, @{ {critical, property, value} })
    T_CNAME, other => ($status, $raw_buffer)

=head2 query($name, $class, $type, $cb)

Raw DNS query without search-domain appending.
Callback: C<($status, $raw_dns_buffer)>.

=head2 gethostbyname($name, $family, $cb)

Legacy resolver.  C<$family> is C<AF_INET> or C<AF_INET6>.
Callback: C<($status, @ip_strings)>.

=head2 reverse($ip_string, $cb)

Reverse DNS (PTR) lookup.  Accepts IPv4 or IPv6 address strings.
Callback: C<($status, @hostnames)>.

=head2 getnameinfo($packed_sockaddr, $flags, $cb)

Full C<getnameinfo>.  C<$packed_sockaddr> from C<Socket::pack_sockaddr_in>
etc.  C<$flags> are C<ARES_NI_*>.
Callback: C<($status, $node, $service)>.

=head2 cancel

Cancel all pending queries.  Callbacks fire with C<ARES_ECANCELLED>.

=head2 set_servers(@addrs)

Replace DNS server list.

=head2 servers

Returns the current server list as a comma-separated string.

=head2 set_local_dev($device)

Bind outgoing queries to a network device (e.g. "eth0").

=head2 set_local_ip4($ipv4_string)

Bind outgoing queries to a local IPv4 address.

=head2 set_local_ip6($ipv6_string)

Bind outgoing queries to a local IPv6 address.

=head2 active_queries

Returns the number of outstanding queries.

=head2 reinit

Re-read system DNS configuration (resolv.conf, hosts file) without
destroying the channel.  Useful for long-running daemons.

=head2 destroy

Explicitly release the c-ares channel and stop all watchers.
Safe to call from within a callback.

=head1 FUNCTIONS

=head2 strerror($status)

Returns human-readable error string.  Callable as function or class method.

=head2 lib_version

Returns the c-ares library version string.

=head1 CALLBACK SAFETY

Callbacks are invoked from within C<ares_process_fd>, which is called
from EV I/O and timer watchers.  Exceptions in callbacks are caught with
C<G_EVAL> and warned (to prevent longjmp through c-ares internals), but
do not propagate.

It is safe to call C<cancel()> or C<destroy()> from within a callback.
Remaining pending queries will receive C<ARES_ECANCELLED>.

File-based lookups (C<lookups =E<gt> 'f'>) may complete synchronously
during the initiating call, so the callback may fire before the method
returns.

=head1 EXPORTS

    :status   - ARES_SUCCESS, ARES_ENODATA, ARES_ETIMEOUT, ...
    :types    - T_A, T_AAAA, T_MX, T_SRV, T_TXT, T_NS, T_SOA, ...
    :classes  - C_IN, C_CHAOS, C_HS, C_ANY
    :flags    - ARES_FLAG_USEVC, ARES_FLAG_EDNS, ARES_FLAG_DNS0x20, ...
    :ai       - ARES_AI_CANONNAME, ARES_AI_ADDRCONFIG, ARES_AI_NOSORT, ...
    :ni       - ARES_NI_NOFQDN, ARES_NI_NUMERICHOST, ...
    :families - AF_INET, AF_INET6, AF_UNSPEC
    :all      - everything

=head1 SEE ALSO

L<EV>, L<https://c-ares.org/>

=head1 LICENSE

Same terms as Perl 5.

=cut
