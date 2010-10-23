package t::lib::TestApp;

use Dancer;
use Dancer::Plugin::Database;

get '/' => sub {
    my $sth = database->prepare('select count(*) from users');
    $sth->execute;
    my $total_users = $sth->fetch();
    $total_users->[0];
};

get '/user/:id' => sub {
    my $sth = database->prepare('select * from users where id = ?');
    $sth->execute( params->{id} );
    my $user = $sth->fetch();
    $user->[1];
};

del '/user/:id' => sub {
    my $sth = database->prepare('delete from users where id = ?');
    $sth->execute(params->{id});
    'ok';
};

1;
