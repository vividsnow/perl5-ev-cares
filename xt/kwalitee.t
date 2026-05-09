use strict;
use warnings;
use Test::More;
plan skip_all => 'Test::Kwalitee required'
    unless eval "use Test::Kwalitee 1.21 'kwalitee_ok'; 1";

# META.yml is produced by `make dist`/`make distdir`, not by a plain
# build. Skip that single metric here so xt/kwalitee.t passes from a
# dev tree.
kwalitee_ok('-has_meta_yml');
done_testing;
