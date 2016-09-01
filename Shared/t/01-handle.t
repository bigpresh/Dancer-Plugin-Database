#!perl

use Test::More;
use DBI;
use Dancer::Plugin::Database::Core::Handle;
use List::Util;

diag( "Testing Dancer::Plugin::Database::Core::Handle "
    . "$Dancer::Plugin::Database::Core::Handle::VERSION, Perl $], $^X"
);


# A few tests that poke directly at the internals of D::P::D::C::Handle.
# For this to work, we'll need a dummy DBI handle to rebless.
# DBD::Sponge ships with DBI, and should be sufficient for our needs.
my $handle = DBI->connect("dbi:Sponge:","","",{ RaiseError => 1 });
bless $handle => 'Dancer::Plugin::Database::Core::Handle';



# Test the construction of ORDER BY clauses.
my @order_by_tests = (
    [ 'foo'                   =>  'ORDER BY "foo"'         ],
    [ ['foo','bar']           =>  'ORDER BY "foo", "bar"'  ],
    [ { asc => 'foo' }        =>  'ORDER BY "foo" ASC'     ],
    [ [ { asc => 'foo' }, { desc => 'bar' } ]
        => 'ORDER BY "foo" ASC, "bar" DESC'                ],
);
my %quoting_tests = (
    'foo' => '"foo"',
    'foo.bar' => '"foo"."bar"',
);



# SQL-generation tests.  Each test is an arrayref consisting of an arrayref of
# params to pass to _generate_sql(), the SQL to expect, and the bind columns to
# expect.
my @sql_tests = (
    {
        name       => "Simple SELECT, no WHERE",
        params     => [ 'SELECT', 'tablename', {} ],
        expect_sql => qq{SELECT * FROM "tablename"},
        expect_bind_params => [],
    },
    {
        name       => "SELECT with named columns, no WHERE",
        params     => ['SELECT', 'tablename', { columns => [qw(one two) ] } ],
        expect_sql => qq{SELECT "one","two" FROM "tablename"},
        expect_bind_params => [],
    },

    {
        name       => "SELECT with literal string WHERE",
        params     => ['SELECT', 'tablename', undef, 'BEER IS GOOD' ],
        expect_sql => qq{SELECT * FROM "tablename" WHERE BEER IS GOOD},
        expect_bind_params => [],
    },

    {
        name       => "SELECT with simple WHERE values",
        params     => [
            'SELECT', 'tablename', undef, { foo => 'One', bar => 'Two' }
        ],
        # Expected order differs - columns alphabetical
        expect_sql => qq{SELECT * FROM "tablename" WHERE "bar"=? AND "foo"=?},
        expect_bind_params => ['Two','One'],
    },

    {
        name       => "SELECT with LIKE",
        params     => [
            'SELECT', 'tablename', undef, 
            { foo => 'One', bar => { like => '%baz%' } }
        ],
        # Expected order differs - columns alphabetical
        expect_sql => qq{SELECT * FROM "tablename" WHERE "bar" LIKE ? AND "foo"=?},
        expect_bind_params => ['%baz%', 'One'],
    },
    {
        name       => "SELECT with ILIKE",
        params     => [
            'SELECT', 'tablename', undef, 
            { foo => 'One', bar => { ilike => '%baz%' } }
        ],
        # Expected order differs - columns alphabetical
        expect_sql => qq{SELECT * FROM "tablename" WHERE "bar" ILIKE ? AND "foo"=?},
        expect_bind_params => ['%baz%', 'One'],
    },
    {
        name       => "INSERT with scalarrefs untouched",
        params     => ['INSERT', 'tablename', { one => \'NOW()', two => '2' } ],
        expect_sql => qq{INSERT INTO "tablename" ("one","two") VALUES (NOW(),?)},
        expect_bind_params => [ 2 ],
    },
    {
        name       => "UPDATE with scalarrefs untouched",
        params     => ['UPDATE', 'tablename', 
            { foo => 'Foo', counter => \'counter+1' },
            { id => 42 },
        ],
        expect_sql => qq{UPDATE "tablename" SET "counter"=counter+1,"foo"=?}
            . qq{ WHERE "id"=?},
        expect_bind_params => ['Foo',42],
    },
);

my $sqlgen_test_count = List::Util::sum(
    map { exists $_->{expect_bind_params} ? 2 : 1 } @sql_tests
);

 plan tests 
    => scalar @order_by_tests + scalar keys(%quoting_tests) + $sqlgen_test_count;

my $i;
for my $test (@order_by_tests) {
    $i++;
    my $res = $handle->_build_order_by_clause($test->[0]);
    is($res, $test->[1],
        sprintf "Order by test %d/%d : %s",
            $i, scalar @order_by_tests, $res
    );
}

for my $identifier (keys %quoting_tests) {
    is(
        $handle->_quote_identifier($identifier),
        $quoting_tests{$identifier},
        "Quoted '$identifier' as '$quoting_tests{$identifier}'"
    );
}

for my $test (@sql_tests) {
    my ($sql, @bind_params) = $handle->_generate_sql(@{ $test->{params} });
    is($sql, $test->{expect_sql}, "Got expected SQL for $test->{name}");
    if (exists $test->{expect_bind_params}) {
        is_deeply(
            \@bind_params,
            $test->{expect_bind_params},
            "Got expected bind params for $test->{name}",
        );
    }
}



