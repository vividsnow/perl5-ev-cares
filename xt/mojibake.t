use strict;
use warnings;
use Test::More;
plan skip_all => 'Test::Mojibake required'
    unless eval 'use Test::Mojibake; 1';
all_files_encoding_ok();
