use strict;
use warnings;
use Test::More;
plan skip_all => 'Test::CPAN::Changes required'
    unless eval 'use Test::CPAN::Changes; 1';
changes_file_ok('Changes');
done_testing;
