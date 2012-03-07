package Dancer::Plugin::Database;

use strict;
use Dancer::Plugin;
use Dancer::Config;
use DBI;
use Dancer::Plugin::Database::Handle;

=encoding utf8

=head1 NAME

Dancer::Plugin::Database - easy database connections for Dancer applications

=cut

our $VERSION = '1.81';

my $settings = undef;

sub _load_db_settings { $settings = plugin_setting(); }

my %handles;
# Hashref used as key for default handle, so we don't have a magic value that
# the user could use for one of their connection names and cause problems
# (Kudos to Igor Bujna for the idea)
my $def_handle = {};

register database => sub {
    my $arg = shift;

    _load_db_settings() if (!$settings);

    # The key to use to store this handle in %handles.  This will be either the
    # name supplied to database(), the hashref supplied to database() (thus, as
    # long as the same hashref of settings is passed, the same handle will be
    # reused) or $def_handle if database() is called without args:
    my $handle_key;
    my $conn_details; # connection settings to use.
    my $handle;


    # Accept a hashref of settings to use, if desired.  If so, we use this
    # hashref to look for the handle, too, so as long as the same hashref is
    # passed to the database() keyword, we'll reuse the same handle:
    if (ref $arg eq 'HASH') {
        $handle_key = $arg;
        $conn_details = $arg;
    } else {
        $handle_key = defined $arg ? $arg : $def_handle;
        $conn_details = _get_settings($arg);
        if (!$conn_details) {
            Dancer::Logger::error(
                "No DB settings for " . ($arg || "default connection")
            );
            return;
        }
    }

    # To be fork safe and thread safe, use a combination of the PID and TID (if
    # running with use threads) to make sure no two processes/threads share
    # handles.  Implementation based on DBIx::Connector by David E. Wheeler.
    my $pid_tid = $$;
    $pid_tid .= '_' . threads->tid if $INC{'threads.pm'};

    # OK, see if we have a matching handle
    $handle = $handles{$pid_tid}{$handle_key} || {};
    
    if ($handle->{dbh}) {
        if ($handle->{dbh}{Active} && $conn_details->{connection_check_threshold} &&
            time - $handle->{last_connection_check}
            < $conn_details->{connection_check_threshold}) 
        {
            return $handle->{dbh};
        } else {
            if (_check_connection($handle->{dbh})) {
                $handle->{last_connection_check} = time;
                return $handle->{dbh};
            } else {
                Dancer::Logger::debug(
                    "Database connection went away, reconnecting"
                );

                Dancer::Factory::Hook->instance->execute_hooks(
                    'database_connection_lost', $handle->{dbh}
                );
                if ($handle->{dbh}) { eval { $handle->{dbh}->disconnect } }
                return $handle->{dbh}= _get_connection($conn_details);

            }
        }
    } else {
        # Get a new connection
        if ($handle->{dbh} = _get_connection($conn_details)) {
            $handle->{last_connection_check} = time;
            $handles{$pid_tid}{$handle_key} = $handle;
            return $handle->{dbh};
        } else {
            return;
        }
    }
};

Dancer::Factory::Hook->instance->install_hooks(
    qw(
        database_connected 
        database_connection_lost
        database_connection_failed
        database_error
    )
);

register_plugin;

# Given the settings to use, try to get a database connection
sub _get_connection {
    my $settings = shift;

    # Assemble the DSN:
    my $dsn = '';
    my $driver = '';
    if ($settings->{dsn}) {
        $dsn = $settings->{dsn};
        ($driver) = $dsn =~ m{dbi:([^:]+)};
    } else {
        $dsn = "dbi:" . $settings->{driver};
        $driver = $settings->{driver};
        my @extra_args;

        # DBD::SQLite wants 'dbname', not 'database', so special-case this
        # (DBI's documentation recommends that DBD::* modules should understand
        # 'database', but older versions of DBD::SQLite didn't; let's make 
        # things easier for our users by handling this for them):
        # (I asked in RT #61117 for DBD::SQLite to support 'database', too; this
        # was included in DBD::SQLite 1.33, released Mon 20 May 2011.
        # Special-casing may as well stay, rather than forcing dependency on
        # DBD::SQLite 1.33.
        if ($driver eq 'SQLite' 
            && $settings->{database} && !$settings->{dbname}) {
            $settings->{dbname} = delete $settings->{database};
        }

        for (qw(database dbname host port)) {
            if (exists $settings->{$_}) {
                push @extra_args, $_ . "=" . $settings->{$_};
            }
        }
        $dsn .= ':' . join(';', @extra_args) if @extra_args;
    }

    # If the app is configured to use UTF-8, the user will want text from the
    # database in UTF-8 to Just Work, so if we know how to make that happen, do
    # so, unless they've set the auto_utf8 plugin setting to a false value.
    my $app_charset = Dancer::Config::setting('charset');
    my $auto_utf8 = exists $settings->{auto_utf8} ?  $settings->{auto_utf8} : 1;
    if (lc $app_charset eq 'utf-8' && $auto_utf8) {
        
        # The option to pass to the DBI->connect call depends on the driver:
        my %param_for_driver = (
            SQLite => 'sqlite_unicode',
            mysql  => 'mysql_enable_utf8',
            Pg     => 'pg_enable_utf8',
        );

        my $param = $param_for_driver{$driver};

        if ($param && !$settings->{dbi_params}{$param}) {
            Dancer::Logger::debug(
                "Adding $param to DBI connection params to enable UTF-8 support"
            );
            $settings->{dbi_params}{$param} = 1;
        }
    }

    # To support the database_error hook, use DBI's HandleError option
    $settings->{dbi_params}{HandleError} = sub {
        my ($error, $handle) = @_;
        Dancer::Factory::Hook->instance->execute_hooks(
            'database_error', $error, $handle
        );
    };


    my $dbh = DBI->connect($dsn, 
        $settings->{username}, $settings->{password}, $settings->{dbi_params}
    );

    if (!$dbh) {
        Dancer::Logger::error(
            "Database connection failed - " . $DBI::errstr
        );
        Dancer::Factory::Hook->instance->execute_hooks(
            'database_connection_failed', $settings
        );
        return;
    } elsif (exists $settings->{on_connect_do}) {
        for (@{ $settings->{on_connect_do} }) {
            $dbh->do($_) or Dancer::Logger::error(
                "Failed to perform on-connect command $_"
            );
        }
    }

    Dancer::Factory::Hook->instance->execute_hooks('database_connected', $dbh);

    # Indicate whether queries generated by quick_query() etc in
    # Dancer::Plugin::Database::Handle should be logged or not; this seemed a
    # little dirty, but DBI's docs encourage it
    # ("You can stash private data into DBI handles via $h->{private_..._*}..")
    $dbh->{private_dancer_plugin_database} = {
        log_queries => $settings->{log_queries} || 0,
    };

    # Re-bless it as a Dancer::Plugin::Database::Handle object, to provide nice
    # extra features (unless the config specifies a different class; if it does,
    # this should be a subclass of Dancer::Plugin::Database::Handle in order to
    # extend the features provided by it, or a direct subclass of DBI::db (or
    # even DBI::db itself) to bypass the features provided by D::P::D::Handle)
    my $handle_class = 
        $settings->{handle_class} || 'Dancer::Plugin::Database::Handle';
    my $package = $handle_class;
    $package =~ s{::}{/}g;
    $package .= '.pm';
    require $package;
    return bless $dbh => $handle_class;
}



# Check the connection is alive
sub _check_connection {
    my $dbh = shift;
    return unless $dbh;
    if ($dbh->{Active} && (my $result = $dbh->ping)) {
        if (int($result)) {
            # DB driver itself claims all is OK, trust it:
            return 1;
        } else {
            # It was "0 but true", meaning the default DBI ping implementation
            # Implement our own basic check, by performing a real simple query.
            my $ok;
            eval {
                $ok = $dbh->do('select 1');
            };
            return $ok;
        }
    } else {
        return;
    }
}

sub _get_settings {
    my $name = shift;
    my $return_settings;

    # If no name given, just return the default settings
    if (!defined $name) {
        $return_settings = { %$settings };
    } else {
        # If there are no named connections in the config, bail now:
        return unless exists $settings->{connections};


        # OK, find a matching config for this name:
        if (my $settings = $settings->{connections}{$name}) {
            $return_settings = { %$settings };
        } else {
            # OK, didn't match anything
            Dancer::Logger::error(
                "Asked for a database handle named '$name' but no matching  "
               ."connection details found in config"
            );
        }
    }

    # We should have something to return now; make sure we have a
    # connection_check_threshold, then return what we found.  In previous
    # versions the documentation contained a typo mentioning
    # connectivity-check-threshold, so support that as an alias.
    if (exists $return_settings->{'connectivity-check-threshold'}
        && !exists $return_settings->{connection_check_threshold})
    {
        $return_settings->{connection_check_threshold}
            = delete $return_settings->{'connectivity-check-threshold'};
    }

    $return_settings->{connection_check_threshold} ||= 30;
    return $return_settings;

}


=head1 SYNOPSIS

    use Dancer;
    use Dancer::Plugin::Database;

    # Calling the database keyword will get you a connected database handle:
    get '/widget/view/:id' => sub {
        my $sth = database->prepare(
            'select * from widgets where id = ?',
        );
        $sth->execute(params->{id});
        template 'display_widget', { widget => $sth->fetchrow_hashref };
    };

    # The handle is a Dancer::Plugin::Database::Handle object, which subclasses
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

Database connection details are read from your Dancer application config - see
below.


=head1 DESCRIPTION

Provides an easy way to obtain a connected DBI database handle by simply calling
the database keyword within your L<Dancer> application

Returns a L<Dancer::Plugin::Database::Handle> object, which is a subclass of
L<DBI>'s C<DBI::db> connection handle object, so it does everything you'd expect
to do with DBI, but also adds a few convenience methods.  See the documentation
for L<Dancer::Plugin::Database::Handle> for full details of those.

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

Connection details will be taken from your Dancer application config file, and
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
performed using C<< $dbh->do >>.

The optional C<log_queries> setting enables logging of queries generated by the
helper functions C<quick_insert> et al in L<Dancer::Plugin::Database::Handle>.
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
L<Dancer::Plugin::Database::Handle> (or L<DBI::db> directly, if you just want to
skip the extra features).


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


=head1 CONVENIENCE FEATURES (quick_select, quick_update, quick_insert, quick_delete)

The handle returned by the C<database> keyword is a
L<Dancer::Plugin::Database::Handle> object, which subclasses the C<DBI::db> DBI
connection handle.  This means you can use it just like you'd normally use a DBI
handle, but extra convenience methods are provided, as documented in the POD for
L<Dancer::Plugin::Database::Handle>.

Examples:

  # Quickly fetch the (first) row whose ID is 42 as a hashref:
  my $row = database->quick_select($table_name, { id => 42 });

  # Fetch all badgers as an array of hashrefs:
  my @badgers = database->quick_select('animals', { genus => 'Mellivora' });

  # Update the row where the 'id' column is '42', setting the 'foo' column to
  # 'Bar':
  database->quick_update($table_name, { id => 42 }, { foo => 'Bar' });

  # Insert a new row, using a named connection (see above)
  database('connectionname')->quick_insert($table_name, { foo => 'Bar' });

  # Delete the row with id 42:
  database->quick_delete($table_name, { id => 42 });

  # Fetch all rows from a table (since version 1.30):
  database->quick_select($table_name, {});

There's more extensive documentation on these features in
L<Dancer::Plugin::Database::Handle>, including using the C<order_by>, C<limit>,
C<columns> options to sort / limit results and include only specific columns.

=head1 HOOKS

This plugin uses Dancer's hooks support to allow you to register code that
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


=head1 BUGS

Please report any bugs or feature requests to C<bug-dancer-plugin-database at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Dancer-Plugin-Database>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Dancer::Plugin::Database


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Dancer-Plugin-Database>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Dancer-Plugin-Database>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Dancer-Plugin-Database>

=item * Search CPAN

L<http://search.cpan.org/dist/Dancer-Plugin-Database/>

=back

You can find the author on IRC in the channel C<#dancer> on <irc.perl.org>.


=head1 LICENSE AND COPYRIGHT

Copyright 2010-12 David Precious.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=head1 SEE ALSO

L<Dancer>

L<DBI>

L<Dancer::Plugin::SimpleCRUD>

=cut

1; # End of Dancer::Plugin::Database
