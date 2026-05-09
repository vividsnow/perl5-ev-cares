use strict;
use warnings;
use Test::More;
plan skip_all => 'Test::DistManifest required'
    unless eval 'use Test::DistManifest; 1';
manifest_ok();
