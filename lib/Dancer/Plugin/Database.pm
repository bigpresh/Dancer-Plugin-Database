package Dancer::Plugin::Database;

use warnings;
use strict;
use Dancer::Plugin;
use DBI;

=head1 NAME

Dancer::Plugin::Database - easy database connections for Dancer

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

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
            if (check_connection($dbh)) {
                $last_connection_check = time;
                return $dbh;
            } else {
                return $dbh = get_connection();
            }
        }
    } else {
        return $dbh = get_connection();
    }
};

register_plugin;

sub get_connection {

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
    return $dbh;
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

=head1 DESCRIPTION

Provides an easy way to obtain a connected DBI database handle by simply calling
the database keyword within your L<Dancer> application.

Connection details will be taken from your application config file, and should
be specified as, for example: 

    plugins:
        database:
            driver: mysql
            dbname: test'
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


=head1 AUTHOR

David Precious, C<< <davidp at preshweb.co.uk> >>

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


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2010 David Precious.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Dancer::Plugin::Database
