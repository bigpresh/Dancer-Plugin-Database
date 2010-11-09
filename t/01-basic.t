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

plan tests => 8;

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

