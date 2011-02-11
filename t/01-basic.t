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

plan tests => 17;

my $dsn = "dbi:SQLite:dbname=:memory:";

setting plugins => { Database => { dsn => $dsn, } };

response_status_is [ GET => '/prepare_db' ], 200, 'db is created';

response_status_is    [ GET => '/' ], 200,   "GET / is found";
response_content_like [ GET => '/' ], qr/2/, "content looks good for /";

response_status_is [ GET => '/user/1' ], 200, 'GET /user/1 is found';

response_content_like [ GET => '/user/1' ], qr/sukria/,
  'content looks good for /user/1';
response_content_like [ GET => '/user/2' ], qr/bigpresh/,
  "content looks good for /user/2";

response_status_is [ DELETE => '/user/2' ], 200, 'DELETE /user/2 is ok';
response_content_like [ GET => '/' ], qr/1/, 'content looks good for /';

# Exercise the extended features (quick_update et al)
response_status_is    [ GET => '/quick_insert/42/Bob' ], 200, 
    "quick_insert returned OK status";
response_content_like [ GET => '/user/42' ], qr/Bob/,
    "quick_insert created a record successfully";

response_content_like [ GET => '/quick_select/42' ], qr/Bob/,
    "quick_select returned the record created by quick_insert";

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

