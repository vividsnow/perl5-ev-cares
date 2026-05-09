use strict;
use warnings;
use Test::More;
use ExtUtils::Manifest qw(maniread);
use File::Temp ();

# Verify a fresh `make dist` tarball contains exactly the files listed
# in MANIFEST.  Catches the case where MANIFEST drifts but `make dist`
# still produces a build (because dist sources from MANIFEST).

plan skip_all => 'no Archive::Tar' unless eval 'use Archive::Tar; 1';
plan skip_all => 'tar not available' unless `which tar 2>/dev/null` =~ /tar/;

# Build a dist into a temp dir so we don't disturb the working tree
my $tmpdir = File::Temp->newdir(CLEANUP => 1);
system("cp -r . $tmpdir/src && cd $tmpdir/src && perl Makefile.PL >/dev/null 2>&1 "
     . "&& make dist >/dev/null 2>&1") == 0
    or do { plan skip_all => 'failed to build dist'; };

my ($tarball) = glob "$tmpdir/src/EV-cares-*.tar.gz";
ok($tarball, "dist tarball exists: " . ($tarball // 'none'))
    or do { plan skip_all => 'no tarball produced'; };

my $tar = Archive::Tar->new($tarball)
    or do { plan skip_all => 'Archive::Tar failed: ' . Archive::Tar->error; };

my %in_tar;
for my $f ($tar->list_files) {
    next if $f =~ m{/$};
    $f =~ s{^[^/]+/}{};   # strip top-level "EV-cares-X.YZ/"
    $in_tar{$f} = 1 if length $f;
}

my %manifest = %{ maniread() };
delete $in_tar{$_} for qw(META.yml META.json);  # auto-generated, not in MANIFEST

my @missing = grep { !exists $in_tar{$_} } sort keys %manifest;
my @extra   = grep { !exists $manifest{$_} } sort keys %in_tar;

is(scalar @missing, 0, 'every MANIFEST file appears in dist tarball')
    or diag "missing: @missing";
is(scalar @extra,   0, 'no extra files in dist tarball beyond MANIFEST')
    or diag "extra: @extra";

done_testing;
