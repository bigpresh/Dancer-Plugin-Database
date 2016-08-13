package Dancer2::Plugin::Database;

use strict;
use warnings;

use Dancer::Plugin::Database::Core;
use Dancer::Plugin::Database::Core::Handle;

use Dancer2::Plugin;

=encoding utf8

=head1 NAME

Dancer2::Plugin::Database - easy database connections for Dancer2 applications

=cut

our $VERSION = '2.17';

register_hook qw(database_connected
                 database_connection_lost
                 database_connection_failed
                 database_error);


my $settings = {};

sub _load_settings {
    my $dsl = shift;
    # ugly plugin1/2 switch - to be removed one day
    if ( $dsl->app->can('with_plugin') ) {
        # plugin2
        # We need this for plugins which use this plugins
        $settings = $dsl->config;
    }
    else {
        # plugin1
        $settings = plugin_setting();
    }
    $settings->{charset} ||= $dsl->setting('charset') || 'utf-8';
}

register database => sub {
    my $dsl = shift;

    my $logger = sub {
        $dsl->log(@_);
    };

    # wasn't working properly calling the Dancer2::Plugin execute_hook
    # directly
    my $hook_exec = sub {
        if ( $dsl->can('execute_plugin_hook') ) {
            # Plugin2
            $dsl->execute_plugin_hook(@_);
        }
        else {
            # old behaviour
            $dsl->execute_hook(@_);
        }
    };

    ## This is mostly for the case the user uses 'set plugins' and
    ## changes configuration during runtime. For example in our test suite.
    _load_settings($dsl);

    my ($dbh, $cfg) = Dancer::Plugin::Database::Core::database( arg => $_[0],
                                                                logger => $logger,
                                                                hook_exec => $hook_exec,
                                                                settings => $settings );
    $settings = $cfg;
    return $dbh;
};

register_plugin;

=head1 SYNOPSIS

    use Dancer2;
    use Dancer2::Plugin::Database;

    # Calling the database keyword will get you a connected database handle:
    get '/widget/view/:id' => sub {
        my $sth = database->prepare(
            'select * from widgets where id = ?',
        );
        $sth->execute(params->{id});
        template 'display_widget', { widget => $sth->fetchrow_hashref };
    };

    # The handle is a Dancer::Plugin::Database::Core::Handle object, which subclasses
    # DBI's DBI::db handle and adds a few convenience features, for example:
    get '/insert/:name' => sub {
        database->quick_insert('people', { name => params->{name} });
    };

    get '/users/:id' => sub {
        template 'display_user', {
            person => database->quick_select('users', { id => params->{id} }),
        };
    };

    dance;

Database connection details are read from your Dancer2 application config - see
below.


=head1 DESCRIPTION

Provides an easy way to obtain a connected DBI database handle by simply calling
the database keyword within your L<Dancer2> application

Returns a L<Dancer::Plugin::Database::Core::Handle> object, which is a subclass of
L<DBI>'s C<DBI::db> connection handle object, so it does everything you'd expect
to do with DBI, but also adds a few convenience methods.  See the documentation
for L<Dancer::Plugin::Database::Core::Handle> for full details of those.

Takes care of ensuring that the database handle is still connected and valid.
If the handle was last asked for more than C<connection_check_threshold> seconds
ago, it will check that the connection is still alive, using either the 
C<< $dbh->ping >> method if the DBD driver supports it, or performing a simple
no-op query against the database if not.  If the connection has gone away, a new
connection will be obtained and returned.  This avoids any problems for
a long-running script where the connection to the database might go away.

Care is taken that handles are not shared across processes/threads, so this
should be thread-safe with no issues with transactions etc.  (Thanks to Matt S
Trout for pointing out the previous lack of thread safety.  Inspiration was
drawn from DBIx::Connector.)

=head1 CONFIGURATION

Connection details will be taken from your Dancer2 application config file, and
should be specified as, for example: 

    plugins:
        Database:
            driver: 'mysql'
            database: 'test'
            host: 'localhost'
            port: 3306
            username: 'myusername'
            password: 'mypassword'
            connection_check_threshold: 10
            dbi_params:
                RaiseError: 1
                AutoCommit: 1
            on_connect_do: ["SET NAMES 'utf8'", "SET CHARACTER SET 'utf8'" ]
            log_queries: 1
            handle_class: 'My::Super::Sexy::Database::Handle'

The C<connection_check_threshold> setting is optional, if not provided, it
will default to 30 seconds.  If the database keyword was last called more than
this number of seconds ago, a quick check will be performed to ensure that we
still have a connection to the database, and will reconnect if not.  This
handles cases where the database handle hasn't been used for a while and the
underlying connection has gone away.

The C<dbi_params> setting is also optional, and if specified, should be settings
which can be passed to C<< DBI->connect >> as its fourth argument; see the L<DBI>
documentation for these.

The optional C<on_connect_do> setting is an array of queries which should be
performed when a connection is established; if given, each query will be
performed using C<< $dbh->do >>.  (If using MySQL, you might want to use this to
set C<SQL_MODE> to a suitable value to disable MySQL's built-in free data loss
'features', for example:

  on_connect_do: "SET SQL_MODE='TRADITIONAL'"

(If you're not familiar with what I mean, I'm talking about the insane default
behaviour of "hmm, this bit of data won't fit the column you're trying to put it
in.. hmm, I know, I'll just munge it to fit, and throw a warning afterwards -
it's not like you're relying on me to, y'know, store what you ask me to store".
See L<http://effectivemysql.com/presentation/mysql-idiosyncrasies-that-bite/> for
just one illustration.  In hindsight, I wish I'd made a sensible C<sql_mode> a
default setting, but I don't want to change that now.)

The optional C<log_queries> setting enables logging of queries generated by the
helper functions C<quick_insert> et al in L<Dancer::Plugin::Database::Core::Handle>.
If you enable it, generated queries will be logged at 'debug' level.  Be aware
that they will contain the data you're passing to/from the database, so be
careful not to enable this option in production, where you could inadvertently
log sensitive information.

If you prefer, you can also supply a pre-crafted DSN using the C<dsn> setting;
in that case, it will be used as-is, and the driver/database/host settings will 
be ignored.  This may be useful if you're using some DBI driver which requires 
a peculiar DSN.

The optional C<handle_class> defines your own class into which database handles
should be blessed.  This should be a subclass of
L<Dancer::Plugin::Database::Core::Handle> (or L<DBI::db> directly, if you just want to
skip the extra features).

You will require slightly different options depending on the database engine
you're talking to.  For instance, for SQLite, you won't need to supply
C<hostname>, C<port> etc, but will need to supply C<database> as the name of the
SQLite database file:

    plugins:
        Database:
            driver: SQLite
            database: 'foo.sqlite'

For Oracle, you may want to pass C<sid> (system ID) to identify a particular
database, e.g.:

    plugins:
        Database:
            driver: Oracle
            host: localhost
            sid: ABC12


If you have any further connection parameters that need to be appended
to the dsn, you can put them in as a hash called dsn_extra. For
example, if you're running mysql on a non-standard socket, you could
have

   plugins:
       Database:
           driver: mysql
           host: localhost
           dsn_extra:
               mysql_socket: /tmp/mysql_staging.sock


=head2 DEFINING MULTIPLE CONNECTIONS

If you need to connect to multiple databases, this is easy - just list them in
your config under C<connections> as shown below:

    plugins:
        Database:
            connections:
                foo:
                    driver: "SQLite"
                    database: "foo.sqlite"
                bar:
                    driver: "mysql"
                    host: "localhost"
                    ....

Then, you can call the C<database> keyword with the name of the database
connection you want, for example:

    my $foo_dbh = database('foo');
    my $bar_dbh = database('bar');


=head1 RUNTIME CONFIGURATION

You can pass a hashref to the C<database()> keyword to provide configuration
details to override any in the config file at runtime if desired, for instance:

    my $dbh = database({ driver => 'SQLite', database => $filename });

(Thanks to Alan Haggai for this feature.)

=head1 AUTOMATIC UTF-8 SUPPORT

As of version 1.20, if your application is configured to use UTF-8 (you've
defined the C<charset> setting in your app config as C<UTF-8>) then support for
UTF-8 for the database connection will be enabled, if we know how to do so for
the database driver in use.

If you do not want this behaviour, set C<auto_utf8> to a false value when
providing the connection details.



=head1 GETTING A DATABASE HANDLE

Calling C<database> will return a connected database handle; the first time it is
called, the plugin will establish a connection to the database, and return a
reference to the DBI object.  On subsequent calls, the same DBI connection
object will be returned, unless it has been found to be no longer usable (the
connection has gone away), in which case a fresh connection will be obtained.

If you have declared named connections as described above in 'DEFINING MULTIPLE
CONNECTIONS', then calling the database() keyword with the name of the
connection as specified in the config file will get you a database handle
connected with those details.

You can also pass a hashref of settings if you wish to provide settings at
runtime.


=head1 CONVENIENCE FEATURES

The handle returned by the C<database> keyword is a
L<Dancer::Plugin::Database::Core::Handle> object, which subclasses the C<DBI::db> DBI
connection handle.  This means you can use it just like you'd normally use a DBI
handle, but extra convenience methods are provided.

There's extensive documentation on these features in
L<Dancer::Plugin::Database::Core::Handle>, including using the C<order_by>, C<limit>,
C<columns> options to sort / limit results and include only specific columns.

=head1 HOOKS

This plugin uses Dancer2's hooks support to allow you to register code that
should execute at given times - for example:

    hook 'database_connected' => sub {
        my $dbh = shift;
        # do something with the new DB handle here
    };

Currrently defined hook positions are:

=over 4

=item C<database_connected>

Called when a new database connection has been established, after performing any
C<on_connect_do> statements, but before the handle is returned.  Receives the
new database handle as a parameter, so that you can do what you need with it.

=item C<database_connection_lost>

Called when the plugin detects that the database connection has gone away.
Receives the no-longer usable handle as a parameter, in case you need to extract
some information from it (such as which server it was connected to).

=item C<database_connection_failed>

Called when an attempt to connect to the database fails.  Receives a hashref of
connection settings as a parameter, containing the settings the plugin was using
to connect (as obtained from the config file).

=item C<database_error>

Called when a database error is raised by C<DBI>.  Receives two parameters: the
error message being returned by DBI, and the database handle in question.

=back

If you need other hook positions which would be useful to you, please feel free
to suggest them!


=head1 AUTHOR

David Precious, C<< <davidp@preshweb.co.uk> >>



=head1 CONTRIBUTING

This module is developed on Github at:

L<http://github.com/bigpresh/Dancer-Plugin-Database>

Feel free to fork the repo and submit pull requests!  Also, it makes sense to 
L<watch the repo|https://github.com/bigpresh/Dancer-Plugin-Database/toggle_watch> 
on GitHub for updates.

Feedback and bug reports are always appreciated.  Even a quick mail to let me
know the module is useful to you would be very nice - it's nice to know if code
is being actively used.

=head1 ACKNOWLEDGEMENTS

Igor Bujna

Franck Cuny

Alan Haggai

Christian Sánchez

Michael Stiller

Martin J Evans

Carlos Sosa

Matt S Trout

Matthew Vickers

Christian Walde

Alberto Simões

James Aitken (LoonyPandora)

Mark Allen (mrallen1)

Sergiy Borodych (bor)

Mario Domgoergen (mdom)

Andrey Inishev (inish777)

Nick S. Knutov (knutov)

Nicolas Franck (nicolasfranck)

mscolly

=head1 BUGS

Please report any bugs or feature requests to C<bug-dancer-plugin-database at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Dancer2-Plugin-Database>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Dancer2::Plugin::Database

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Dancer2-Plugin-Database>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Dancer2-Plugin-Database>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Dancer2-Plugin-Database>

=item * Search CPAN

L<http://search.cpan.org/dist/Dancer2-Plugin-Database/>

=back

You can find the author on IRC in the channel C<#dancer> on <irc.perl.org>.


=head1 LICENSE AND COPYRIGHT

Copyright 2010-2016 David Precious.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=head1 SEE ALSO

L<Dancer::Plugin::Database::Core> and L<Dancer::Plugin::Database::Core::Handle>

L<Dancer>, L<Dancer2>

L<DBI>

L<Dancer::Plugin::SimpleCRUD>

=cut

1; # End of Dancer2::Plugin::Database
