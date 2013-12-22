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

plan tests => 43;

my $dsn = "dbi:SQLite:dbname=:memory:";

my $conf = {
            Database => {
                         dsn => $dsn,
                         connection_check_threshold => 0.1,
                         dbi_params => {
                                        RaiseError => 0,
                                        PrintError => 0,
                                        PrintWarn  => 0,
                                       },
                         handle_class => 'TestHandleClass',
                        }
           };


set plugins => $conf;
set logger => 'capture';
set log => 'debug';

response_content_is   [ GET => '/connecthookfired' ], 1,
    'database_connected hook fires';

response_content_is   [ GET => '/errorhookfired' ], 1,
    'database_error hook fires';

response_content_is   [ GET => '/isa/DBI::db' ], 1,
    "handle isa('DBI::db')";
response_content_is   [ GET => '/isa/Dancer::Plugin::Database::Core::Handle' ], 1,
    "handle isa('Dancer::Plugin::Database::Core::Handle')";
response_content_is   [ GET => '/isa/TestHandleClass' ], 1,
    "handle isa('TestHandleClass')";
response_content_is   [ GET => '/isa/duck' ], 0, # reverse duck-typing ;)
    "handle is not a duck";

response_status_is    [ GET => '/prepare_db' ], 200, 'db is created';

response_status_is    [ GET => '/' ], 200,   "GET / is found";
response_content_like [ GET => '/' ], qr/7/, 
    "content looks good for / (7 users afiter DB initialisation)";

response_status_is [ GET => '/user/1' ], 200, 'GET /user/1 is found';

response_content_like [ GET => '/user/1' ], qr/sukria/,
  'content looks good for /user/1';
response_content_like [ GET => '/user/2' ], qr/bigpresh/,
  "content looks good for /user/2";

response_status_is [ DELETE => '/user/3' ], 200, 'DELETE /user/3 is ok';
response_content_like [ GET => '/' ], qr/6/, 
    'content looks good for / (6 users after deleting one)';

# Exercise the extended features (quick_update et al)
response_status_is    [ GET => '/quick_insert/42/Bob' ], 200, 
    "quick_insert returned OK status";
response_content_like [ GET => '/user/42' ], qr/Bob/,
    "quick_insert created a record successfully";

response_content_like   [ GET => '/quick_select/42' ], qr/Bob/,
    "quick_select returned the record created by quick_insert";
response_content_unlike [ GET => '/quick_select/69' ], qr/Bob/,
    "quick_select doesn't return non-matching record";

response_content_like [ GET => '/quick_select/1/category' ], qr/admin/,
  'content looks good for /quick_select/1/category';
response_content_like [ GET => '/quick_select/2/name' ], qr/bigpresh/,
  'content looks good for /quick_select/2/name';

response_content_like [ GET => '/quick_lookup/bigpresh' ], qr/2/,
  'content looks good for /quick_lookup/bigpresh';

# Test quick_count functions

response_content_is [ GET => '/quick_count/admin'], 2, 'quick_count shows 2 admins';

response_content_like   [ GET => '/complex_where/4' ], qr/mousey/,
    "Complex where clause succeeded";

response_content_like   [ GET => '/complex_not/42' ], qr/sukria/,
    "Complex not where clause succeeded";

response_content_like   [ GET => '/set_op/2' ], qr/bigpresh/,
    "set operation where clause succeeded";

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


# Test that we can fetch only the columns we want
response_content_like [ GET => '/quick_select_specific_cols/name' ],
    qr/^bigpresh$/m,
    'Fetched a single specified column OK';

response_content_like [ GET => '/quick_select_specific_cols/name/category' ],
    qr/^bigpresh:admin$/m,
    'Fetched multiple specified columns OK';

# Test that we can limit the number of rows we get back:
response_content_is [ GET => '/quick_select_with_limit/1'],
    "1",
    "User-specified LIMIT works (1 row)";
response_content_is [ GET => '/quick_select_with_limit/2'],
    "2",
    "User-specified LIMIT works (2 row)";

# Test that order_by gives us rows in desired order
response_content_is [ GET => '/quick_select_sorted' ],
    "bigpresh:bodger:mousey:mystery1:mystery2:sukria",
    "Records sorted properly";
response_content_is [ GET => '/quick_select_sorted_rev' ],
    "sukria:mystery2:mystery1:mousey:bodger:bigpresh",
    "Records sorted properly in descending order";

# Use where and order_by together
# This didn't work as the WHERE and ORDER BY clauses were concatenated without
# a space, as per https://github.com/bigpresh/Dancer-Plugin-Database/pull/27
response_content_is [ GET => '/quick_select_sorted_where' ],
    "mystery1:mystery2";

# Test that runtime configuration gives us a handle, too:
response_status_is    [ GET => '/runtime_config' ], 200,
    "runtime_config returned OK status";
response_content_like [ GET => '/runtime_config' ], qr/ok/,
    "runtime_config got a usable database handle";

# Test that we get the same handle each time we call the database() keyword
# (i.e., that handles are cached appropriately)
response_content_like [ GET => '/handles_cached' ], qr/Same handle returned/;

# ... and that we get the same handle each time we call the database() keyword
# after a reconnection (see PR-44)
response_content_like [ GET => '/handles_cached_after_reconnect' ], 
    qr/New handle cached after reconnect/;


# Test that the database_connection_lost hook fires when the connection goes
# away
response_content_is [ GET => '/database_connection_lost_fires' ], 1,
    'database_connection_lost hook fires';

# Test that the database_connection_failed hook fires when we can't connect
response_content_is [ GET => '/database_connection_failed_fires' ], 1,
    'database_connection_failed hook fires';
