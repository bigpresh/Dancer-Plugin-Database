#!perl

use Test::More;
use DBI;
use Dancer::Plugin::Database::Core;
use List::Util;

diag( "Testing Dancer::Plugin::Database::Core "
    . "$Dancer::Plugin::Database::Core::VERSION, Perl $], $^X"
);


# Test that we cache handles even for runtime config hashrefs
# GH-75
my $db_keyword = *Dancer::Plugin::Database::Core::database{CODE};
diag "db_keyword: $db_keyword";
is(
    $db_keyword->( arg => { driver => 'SQLite', database => ':memory:'}),
    $db_keyword->( arg => { driver => 'SQLite', database => ':memory:'}),
    "Same DB handle (cached) even for runtime config",
);


