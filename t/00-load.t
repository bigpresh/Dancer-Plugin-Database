#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Dancer::Plugin::Database' ) || print "Bail out!
";
}

diag( "Testing Dancer::Plugin::Database $Dancer::Plugin::Database::VERSION, Perl $], $^X" );
