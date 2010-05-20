package Dancer::Plugin::Database;

use strict;
use Dancer::Plugin;
use DBI;

=head1 NAME

Dancer::Plugin::Database - easy database connections for Dancer applications

=cut

our $VERSION = '0.04';

my $dbh;
my $last_connection_check;
my $settings = plugin_setting;
$settings->{connection_check_threshold} ||= 30;

register database => sub {
    if ($dbh) {
        if (time - $last_connection_check
            < $settings->{connection_check_threshold}) {
            return $dbh;
        } else {
            if (_check_connection($dbh)) {
                $last_connection_check = time;
                return $dbh;
            } else {
                Dancer::Logger->debug(
                    "Database connection went away, reconnecting"
                );
                if ($dbh) { $dbh->disconnect; }
                return $dbh = _get_connection();
            }
        }
    } else {
        return $dbh = _get_connection();
    }
};

register_plugin;

sub _get_connection {

    # Assemble the DSN:
    my $dsn;
    if ($settings->{dsn}) {
        $dsn = $settings->{dsn};
    } else {
        $dsn = "dbi:" . $settings->{driver};
        for (qw(database host port)) {
            if (exists $settings->{$_}) {
                $dsn .= ":$_=". $settings->{$_};
            }
        }
    }

    my $dbh = DBI->connect($dsn, 
        $settings->{username}, $settings->{password}
    );

    if (!$dbh) {
        Dancer::Logger->error(
            "Database connection failed - " . $DBI::errstr
        );
    }
    $last_connection_check = time;
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


=head1 SYNOPSIS

    use Dancer;
    use Dancer::Plugin::Database;

    # Calling the database keyword will get you a connected DBI handle:
    get '/widget/view/:id' => sub {
        my $sth = database->prepare(
            'select * from widgets where id = ?',
            {}, params->{id}
        );
        $sth->execute;
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
ago, it will perform a simple no-op query against the database and check that it
worked; if not, a new connection will be obtained.  This avoids any problems for
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

The C<connectivity-check-threshold> setting is optional, if not provided, it
will default to 30 seconds.  If the database keyword was last called more than
this number of seconds ago, a quick check will be performed to ensure that we
still have a connection to the database, and will reconnect if not.  This
handles cases where the database handle hasn't been used for a while and the
underlying connection has gone away.

Calling C<database> will return a connected database handle; the first time it is
called, the plugin will establish a connection to the database, and return a
reference to the DBI object.

If you prefer, you can also supply a pre-crafted DSN; in that case, it will be
used as-is, and the driver/database/host settings will be ignored.  This may be
useful if you're using some DBI driver which requires a peculiar DSN.


=head1 AUTHOR

David Precious, C<< <davidp@preshweb.co.uk> >>


=head1 CONTRIBUTING

This module is developed on Github at:

L<http://github.com/bigpresh/Dancer-Plugin-Database>

Feel free to fork the repo and submit pull requests!


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
