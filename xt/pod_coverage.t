use strict;
use warnings;
use Test::More;
plan skip_all => 'Test::Pod::Coverage 1.08+ required'
    unless eval 'use Test::Pod::Coverage 1.08; 1';

all_pod_coverage_ok({
    also_private => [qr/^(?:BOOT|CLONE|DESTROY|ARES_|T_|C_|AF_|_wrap)/],
});
