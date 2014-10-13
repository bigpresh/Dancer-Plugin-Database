use strict;
use warnings;

use Test::More import => ['!pass'];

use HTTP::Request::Common qw(GET HEAD PUT POST DELETE);
use Plack::Test;

eval { require DBD::SQLite };
if ($@) {
    plan skip_all => 'DBD::SQLite required to run these tests';
}

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
                         handle_class => 't::lib::TestHandleClass',
                        }
           };

use t::lib::TestApp;
{
    package t::lib::TestApp;
    set plugins => $conf;
    set logger => 'capture';
    set log => 'debug';
}

my $app = t::lib::TestApp->to_app;
is(ref $app, "CODE", "Got a code ref");

test_psgi $app, sub {
    my $cb = shift;

    {
        my $res = $cb->(GET '/connecthookfired');
        is $res->content, 1, 'database_connected hook fires';
    }

    {
        my $res = $cb->(GET '/errorhookfired');
        is $res->content, 1, 'database_error hook fires';
    }

    {
        my $res = $cb->( GET '/isa/DBI::db');
        is $res->content, 1, "handle isa('DBI::db')";
    }

    {
        my $res = $cb->( GET '/isa/Dancer::Plugin::Database::Core::Handle');
        is $res->content, 1, "handle isa('Dancer::Plugin::Database::Core::Handle')";
    }

    {
        my $res = $cb->( GET '/isa/t::lib::TestHandleClass');
        is $res->content, 1, "handle isa('t::lib::TestHandleClass')";
    }

    {
        my $res = $cb->( GET '/isa/duck' );
        is $res->content, 0, "handle is not a duck"; # reverse duck-typing ;)
    }

    {
        my $res = $cb->( GET '/prepare_db' );
        is $res->code, 200, 'db is created';
    }

    {
        my $res = $cb->( GET '/' );
        is $res->code, 200,   "GET / is found";
    }

    {
        my $res = $cb->( GET '/' );
        like $res->content, qr/7/, "content looks good for / (7 users afiter DB initialisation)";
    }
    {
        my $res = $cb->(GET '/user/1');
        is $res->code, 200,'GET /user/1 is found';
    }
    {
        my $res = $cb->( GET '/user/1' );
        like $res->content, qr/sukria/, 'content looks good for /user/1';
    }
    {
        my $res = $cb->(GET '/user/2' );
        like $res->content, qr/bigpresh/, "content looks good for /user/2";
    }
    {
        my $res = $cb->( DELETE '/user/3' );
        is $res->code, 200, 'DELETE /user/3 is ok';
    }
    {
        my $res = $cb->( GET '/' ); 
        like $res->content, qr/6/, 'content looks good for / (6 users after deleting one)';
    }

    # Exercise the extended features (quick_update et al)
    {
        my $res = $cb->( GET '/quick_insert/42/Bob' ); 
        is $res->code, 200, "quick_insert returned OK status";
    }

    {
        my $res = $cb->( GET '/user/42' );
        like $res->content, qr/Bob/, "quick_insert created a record successfully";
    }
    {
        my $res = $cb->( GET '/quick_select/42' );
        like $res->content, qr/Bob/, "quick_select returned the record created by quick_insert";
    }
    {
        my $res = $cb->(GET '/quick_select/69' );
        unlike $res->content, qr/Bob/, "quick_select doesn't return non-matching record";
    }
    {
        my $res = $cb->(GET '/quick_select/1/category' );
        like $res->content, qr/admin/, 'content looks good for /quick_select/1/category';
    }
    {
        my $res = $cb->( GET '/quick_select/2/name' );
        like $res->content, qr/bigpresh/, 'content looks good for /quick_select/2/name';
    }
    {
        my $res = $cb->(GET '/quick_lookup/bigpresh' );
        like $res->content, qr/2/, 'content looks good for /quick_lookup/bigpresh';
    }

  # Test quick_count functions

    {
        my $res = $cb->( GET '/quick_count/admin');
        is $res->content, 2, 'quick_count shows 2 admins';
    }
    {
        my $res = $cb->( GET '/complex_where/4' );
        like $res->content, qr/mousey/, "Complex where clause succeeded";
    }
    {
        my $res = $cb->( GET '/complex_not/42' );
        like $res->content, qr/sukria/, "Complex not where clause succeeded";
    }
    {
        my $res = $cb->( GET '/set_op/2' );
        like $res->content, qr/bigpresh/, "set operation where clause succeeded";
    }
    {
        my $res = $cb->( GET '/quick_select_many' );
        like $res->content, qr/\b bigpresh,sukria \b/x,
          "quick_select returns multiple records in list context";
    }

    {
        my $res = $cb->( GET '/quick_update/42/Billy' );
        is $res->code, 200, "quick_update returned OK status";
    }
    {
        my $res = $cb->( GET '/user/42' );
        like $res->content, qr/Billy/, "quick_update updated a record successfully";
    }
    {
        my $res = $cb->( GET '/quick_delete/42' );
        is $res->code, 200, "quick_delete returned OK status";
    }
    {
        my $res = $cb->( GET '/user/42' );
        like $res->content, qr/No such user/,
          "quick_delete deleted a record successfully";
    }

    # Test that we can fetch only the columns we want
    {
        my $res = $cb->(GET '/quick_select_specific_cols/name');
        like $res->content, qr/^bigpresh$/m, 'Fetched a single specified column OK';
    }
    {
        my $res = $cb->( GET '/quick_select_specific_cols/name/category' );
        like $res->content, qr/^bigpresh:admin$/m, 'Fetched multiple specified columns OK';
    }

    # Test that we can limit the number of rows we get back:
    {
        my $res = $cb->( GET '/quick_select_with_limit/1' );
        is $res->content, "1", "User-specified LIMIT works (1 row)";
    }

    {
        my $res = $cb->( GET '/quick_select_with_limit/2');
        is $res->content, "2", "User-specified LIMIT works (2 row)";
    }

    # Test that order_by gives us rows in desired order
    {
        my $res = $cb->(GET '/quick_select_sorted' );
        is $res->content, "bigpresh:bodger:mousey:mystery1:mystery2:sukria",
          "Records sorted properly";
    }
    {
        my $res = $cb->(GET '/quick_select_sorted_rev' );
        is $res->content, "sukria:mystery2:mystery1:mousey:bodger:bigpresh",
          "Records sorted properly in descending order";
    }

    # Use where and order_by together
    # This didn't work as the WHERE and ORDER BY clauses were concatenated without
    # a space, as per https://github.com/bigpresh/Dancer-Plugin-Database/pull/27
    {
        my $res = $cb->( GET '/quick_select_sorted_where' );
        is $res->content, "mystery1:mystery2";
    }

    # Test that runtime configuration gives us a handle, too:
    {
        my $res = $cb->( GET '/runtime_config' );
        is $res->code, 200, "runtime_config returned OK status";
    }
    {
        my $res = $cb->( GET '/runtime_config' );
        like $res->content, qr/ok/, "runtime_config got a usable database handle";
    }

    # Test that we get the same handle each time we call the database() keyword
    # (i.e., that handles are cached appropriately)
    {
        my $res = $cb->( GET '/handles_cached' );
        like $res->content, qr/Same handle returned/;
    }

    # Test that the database_connection_lost hook fires when the connection goes
    # away
    {
        my $res = $cb->(GET '/database_connection_lost_fires' );
        is $res->content, 1, 'database_connection_lost hook fires';
    }
    # Test that the database_connection_failed hook fires when we can't connect
    {
        my $res = $cb->( GET '/database_connection_failed_fires' );
        is $res->content, 1, 'database_connection_failed hook fires';
    }
};

done_testing();

__END__



