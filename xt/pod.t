use strict;
use warnings;
use Test::More;
plan skip_all => 'Test::Pod 1.22+ required' unless eval 'use Test::Pod 1.22; 1';
all_pod_files_ok();
