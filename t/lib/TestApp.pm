package t::lib::TestApp;

use Dancer;
use Dancer::Plugin::Database;

get '/prepare_db' => sub {

    my @sql = (
        q/create table users (id INTEGER, name VARCHAR, category VARCHAR)/,
        q/insert into users values (1, 'sukria', 'admin')/,
        q/insert into users values (2, 'bigpresh', 'admin')/,
        q/insert into users values (3, 'badger', 'animal')/,
    );

    database->do($_) for @sql;
    'ok';
};

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
    $user->[1] || "No such user";
};

del '/user/:id' => sub {
    my $sth = database->prepare('delete from users where id = ?');
    $sth->execute( params->{id} );
    'ok';
};


# Routes to exercise some of the extended features:
get '/quick_insert/:id/:name' => sub {
    database->quick_insert('users',
        { id => params->{id}, name => params->{name}, category => 'user' },
    );
    'ok';
};

get '/quick_update/:id/:name' => sub {
    database->quick_update('users',
        { id => params->{id}     },
        { name => params->{name} },
    );
    'ok';
};

get '/quick_delete/:id' => sub {
    database->quick_delete('users', { id => params->{id} });
    'ok';
};

get '/quick_select/:id' => sub {
    my $row = database->quick_select('users', { id => params->{id} });
    return $row ? join(',', values %$row) 
        : "No matching user"; 
};

get '/quick_select/:id/:parm' => sub {
    my $row = database->quick_select('users', { id => params->{id} }, 
         [ 'id', params->{parm} ]);
    return $row ? join(',', values %$row) 
        : "No matching user"; 
};

get '/quick_lookup/:name' => sub {
    my $id = database->quick_lookup('users', { name => params->{name} },
        'id');

    return $id;
};

get '/complex_where/:id' => sub {
    my $row = database->quick_select('users', { id => { 'gt' => '4' } });
    return $row ? join(',', values %$row) 
        : "No matching user"; 
};

get '/complex_not/:id' => sub {
    my $row = database->quick_select('users', { category => { 'is' => undef, 'not' => 1 } });
    return $row ? join(',', values %$row) 
        : "No matching user"; 
};

get '/set_op/:id' => sub {
    my $row = database->quick_select('users', { id => [ params->{id} ] });
    return $row ? join(',', values %$row) 
        : "No matching user"; 
};

get '/quick_select_many' => sub {
        my @users = database->quick_select('users', {  category => 'admin' });
        return join ',', sort map { $_->{name} } @users;
};

# Check we can get a handle by passing a hashref of settings, too:
get '/runtime_config' => sub {
    my $dbh = database({ driver => 'SQLite', database => ':memory:'});
    $dbh ? 'ok' : '';
};

# Check we get the same handle each time we call database()
get '/handles_cached' => sub {
    database() eq database() and return "Same handle returned";
};

1;
