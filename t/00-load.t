#!perl
# had -T

use Test::More import => ['!pass'], tests => 1;
use Dancer;

BEGIN {
    use_ok( 'Dancer::Plugin::Database' ) || print "Bail out!
";
}

diag( "Testing Dancer::Plugin::Database $Dancer::Plugin::Database::VERSION, with Dancer $Dancer::VERSION in Perl $], $^X" );
