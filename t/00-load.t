#!perl -T

use Dancer::Test;
use Test::More;
BEGIN {
    use_ok( 'Dancer::Plugin::Database' ) || print "Bail out!";
    use_ok ( 'Dancer::Plugin::Database::Handle ') || print "Bail out!";
}

diag( "Testing Dancer::Plugin::Database $Dancer::Plugin::Database::VERSION, Perl $], $^X" );
done_testing;
