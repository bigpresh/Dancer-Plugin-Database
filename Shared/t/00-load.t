#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 2;

BEGIN {
    use_ok( 'Dancer::Plugin::Database::Core' ) || print "Bail out!\n";
    use_ok( 'Dancer::Plugin::Database::Core::Handle' ) || print "Bail out!\n";
}

diag( "Testing Dancer::Plugin::Database::Core $Dancer::Plugin::Database::Core::VERSION, Perl $], $^X" );
