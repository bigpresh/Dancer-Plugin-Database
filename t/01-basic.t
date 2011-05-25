use strict;
use warnings;

use Test::More import => ['!pass'];

use t::lib::TestApp;
use Dancer ':syntax';
use Dancer::Test;

eval { require DBD::SQLite };
if ($@) {
    plan skip_all => 'DBD::SQLite required to run these tests';
}

plan tests => 20;

my $dsn = "dbi:SQLite:dbname=:memory:";

setting plugins => { Database => { dsn => $dsn, } };

response_status_is [ GET => '/prepare_db' ], 200, 'db is created';

response_status_is    [ GET => '/' ], 200,   "GET / is found";
response_content_like [ GET => '/' ], qr/3/, 
    "content looks good for / (3 users afiter DB initialisation)";

response_status_is [ GET => '/user/1' ], 200, 'GET /user/1 is found';

response_content_like [ GET => '/user/1' ], qr/sukria/,
  'content looks good for /user/1';
response_content_like [ GET => '/user/2' ], qr/bigpresh/,
  "content looks good for /user/2";

response_status_is [ DELETE => '/user/3' ], 200, 'DELETE /user/3 is ok';
response_content_like [ GET => '/' ], qr/2/, 
    'content looks good for / (2 users after deleting one)';

# Exercise the extended features (quick_update et al)
response_status_is    [ GET => '/quick_insert/42/Bob' ], 200, 
    "quick_insert returned OK status";
response_content_like [ GET => '/user/42' ], qr/Bob/,
    "quick_insert created a record successfully";

response_content_like   [ GET => '/quick_select/42' ], qr/Bob/,
    "quick_select returned the record created by quick_insert";
response_content_unlike [ GET => '/quick_select/69' ], qr/Bob/,
    "quick_select doesn't return non-matching record";

response_content_like  [ GET => '/quick_select_many' ], 
    qr/\b bigpresh,sukria \b/x,
    "quick_select returns multiple records in list context";

response_status_is    [ GET => '/quick_update/42/Billy' ], 200,
    "quick_update returned OK status";
response_content_like [ GET => '/user/42' ], qr/Billy/,
    "quick_update updated a record successfully";

response_status_is    [ GET => '/quick_delete/42' ], 200,
    "quick_delete returned OK status";
response_content_like [ GET => '/user/42' ], qr/No such user/,
    "quick_delete deleted a record successfully";

# Test that runtime configuration gives us a handle, too:
response_status_is    [ GET => '/runtime_config' ], 200,
    "runtime_config returned OK status";
response_content_like [ GET => '/runtime_config' ], qr/ok/,
    "runtime_config got a usable database handle";

# Test that we get the same handle each time we call the database() keyword
# (i.e., that handles are cached appropriately)
response_content_like [ GET => '/handles_cached' ], qr/Same handle returned/;
