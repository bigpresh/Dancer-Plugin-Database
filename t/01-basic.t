use strict;
use warnings;

use Test::More import => ['!pass'];

use File::Spec;
use File::Temp qw/tempdir/;

use t::lib::TestApp;
use Dancer ':syntax';
use Dancer::Test;

eval { require DBD::SQLite };
if ($@) {
    plan skip_all => 'DBD::SQLite required to run these tests';
}

my $dir = tempdir( CLEANUP => 1 );
my $db = File::Spec->catfile( $dir, 'test.db' );

my $dsn = "dbi:SQLite:dbname=$db";

my $dbh;

$dbh = DBI->connect($dsn);

my @sql = (
    q/create table users (id INTEGER, name VARCHAR(64))/,
    q/insert into users values (1, 'sukria')/,
    q/insert into users values (2, 'bigpresh')/,
);

$dbh->do($_) for @sql;

plan tests => 7;

setting plugins => { Database => { dsn => $dsn, } };

response_status_is    [ GET => '/' ], 200,   "GET / is found";
response_content_like [ GET => '/' ], qr/2/, "content looks god for /";

response_status_is [ GET => '/user/1' ], 200, 'GET /user/1 is found';

response_content_like [ GET => '/user/1' ], qr/sukria/,
  'content looks good for /user/1';
response_content_like [ GET => '/user/2' ], qr/bigpresh/,
  "content looks good for /user/2";

response_status_is [ DELETE => '/user/2' ], 200, 'DELETE /user/2 is ok';
response_content_like [ GET => '/' ], qr/1/, 'content looks good for /';

