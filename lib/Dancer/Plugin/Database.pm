package Dancer::Plugin::Database;

use strict;
use Dancer::Plugin;
use DBI;

=head1 NAME

Dancer::Plugin::Database - easy database connections for Dancer applications

=cut

our $VERSION = '0.10';

my $settings = undef;

sub _load_db_settings { $settings = plugin_setting; }

my %handles;
# Hashref used as key for default handle, so we don't have a magic value that
# the user could use for one of their connection names and cause problems
# (Kudos to Igor Bujna for the idea)
my $def_handle = {};

register database => sub {
    my $name = shift;

    _load_db_settings() if (!$settings);
    
    my $handle = defined($name) ? $handles{$name} : $def_handle;
    my $settings = _get_settings($name);

    if ($handle->{dbh}) {
        if (time - $handle->{last_connection_check}
            < $settings->{connection_check_threshold}) {
            return $handle->{dbh};
        } else {
            if (_check_connection($handle->{dbh})) {
                $handle->{last_connection_check} = time;
                return $handle->{dbh};
            } else {
                Dancer::Logger::debug(
                    "Database connection went away, reconnecting"
                );
                if ($handle->{dbh}) { $handle->{dbh}->disconnect; }
                return $handle->{dbh}= _get_connection();
            }
        }
    } else {
        # Get a new connection
        if (!$settings) {
            Dancer::Logger::error(
                "No DB settings named $name, so cannot connect"
            );
            return;
        }
        if ($handle->{dbh} = _get_connection($settings)) {
            $handle->{last_connection_check} = time;
            return $handle->{dbh};
        } else {
            return;
        }
    }
};

register_plugin;

# Given the settings to use, try to get a database connection
sub _get_connection {
    my $settings = shift;

    # Assemble the DSN:
    my $dsn;
    if ($settings->{dsn}) {
        $dsn = $settings->{dsn};
    } else {
        $dsn = "dbi:" . $settings->{driver};
        my @extra_args;

        # DBD::SQLite wants 'dbname', not 'database', so special-case this
        # (DBI's documentation recommends that DBD::* modules should understand
        # 'database', but older versions of DBD::SQLite didn't; let's make 
        # things easier for our users by handling this for them):
        # (DBD::SQLite will support 'database', too, as of 1.32 when it's
        # released)
        if ($settings->{driver} eq 'SQLite' 
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

    my $dbh = DBI->connect($dsn, 
        $settings->{username}, $settings->{password}, $settings->{dbi_params}
    );

    if (!$dbh) {
        Dancer::Logger::error(
            "Database connection failed - " . $DBI::errstr
        );
    } elsif (exists $settings->{on_connect_do}) {
        for (@{ $settings->{on_connect_do} }) {
            $dbh->do($_) or Dancer::Logger::error(
                "Failed to perform on-connect command $_"
            );
        }
    }

    return $dbh;
}



# Check the connection is alive
sub _check_connection {
    my $dbh = shift;
    return unless $dbh;
    if (my $result = $dbh->ping) {
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
    # (Take a copy and remove the connections key, so we have only the main
    # connection details)
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
    
    # We should have soemthing to return now; remove any unrelated connections
    # (only needed if this is the default connection), and make sure we have a
    # connection_check_threshold, then return what we found
    delete $return_settings->{connections};
    $return_settings->{connection_check_threshold} ||= 30;
    return $return_settings;

}


=head1 SYNOPSIS

    use Dancer;
    use Dancer::Plugin::Database;

    # Calling the database keyword will get you a connected DBI handle:
    get '/widget/view/:id' => sub {
        my $sth = database->prepare(
            'select * from widgets where id = ?',
        );
        $sth->execute(params->{id});
        template 'display_widget', { widget => $sth->fetchrow_hashref };
    };

    dance;

Database connection details are read from your Dancer application config - see
below.


=head1 DESCRIPTION

Provides an easy way to obtain a connected DBI database handle by simply calling
the database keyword within your L<Dancer> application.

Takes care of ensuring that the database handle is still connected and valid.
If the handle was last asked for more than C<connection_check_threshold> seconds
ago, it will check that the connection is still alive, using either the 
C<< $dbh->ping >> method if the DBD driver supports it, or performing a simple
no-op query against the database if not.  If the connection has gone away, a new
connection will be obtained and returned.  This avoids any problems for
a long-running script where the connection to the database might go away.

=head1 CONFIGURATION

Connection details will be taken from your Dancer application config file, and
should be specified as, for example: 

    plugins:
        Database:
            driver: 'mysql'
            database: 'test'
            host: 'localhost'
            username: 'myusername'
            password: 'mypassword'
            connectivity-check-threshold: 10
            dbi_params:
                RaiseError: 1
                AutoCommit: 1
            on_connect_do: ["SET NAMES 'utf8'", "SET CHARACTER SET 'utf8'" ]

The C<connectivity-check-threshold> setting is optional, if not provided, it
will default to 30 seconds.  If the database keyword was last called more than
this number of seconds ago, a quick check will be performed to ensure that we
still have a connection to the database, and will reconnect if not.  This
handles cases where the database handle hasn't been used for a while and the
underlying connection has gone away.

The C<dbi_params> setting is also optional, and if specified, should be settings
which can be passed to C<< DBI->connect >> as its third argument; see the L<DBI>
documentation for these.

The optional C<on_connect_do> setting is an array of queries which should be
performed when a connection is established; if given, each query will be
performed using C<< $dbh->do >>.

If you prefer, you can also supply a pre-crafted DSN using the C<dsn> setting;
in that case, it will be used as-is, and the driver/database/host settings will 
be ignored.  This may be useful if you're using some DBI driver which requires 
a peculiar DSN.


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

=head1 AUTHOR

David Precious, C<< <davidp@preshweb.co.uk> >>



=head1 CONTRIBUTING

This module is developed on Github at:

L<http://github.com/bigpresh/Dancer-Plugin-Database>

Feel free to fork the repo and submit pull requests!


=head1 ACKNOWLEDGEMENTS

Igor Bujna

Franck Cuny

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

Copyright 2010 David Precious.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=head1 SEE ALSO

L<Dancer>

L<DBI>



=cut

1; # End of Dancer::Plugin::Database
