#!perl
# had -T

use Test::More import => ['!pass'], tests => 1;
use Dancer2;

BEGIN {
    use_ok( 'Dancer2::Plugin::Database' ) || print "Bail out!
";
}

diag( "Testing Dancer2::Plugin::Database $Dancer2::Plugin::Database::VERSION, with Dancer2 $Dancer2::VERSION in Perl $], $^X" );
