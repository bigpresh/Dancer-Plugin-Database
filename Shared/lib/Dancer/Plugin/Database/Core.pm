package Dancer::Plugin::Database::Core;

use 5.006;
use strict;
use warnings FATAL => 'all';

=head1 NAME

Dancer::Plugin::Database::Core - Shared core for D1 and D2 Database plugins

=cut

our $VERSION = '0.20';

my %handles;
# Hashref used as key for default handle, so we don't have a magic value that
# the user could use for one of their connection names and cause problems
# (Kudos to Igor Bujna for the idea)
my $def_handle = {};

=head1 SYNOPSIS

This module should not be used directly. It is a shared library for
L<Dancer::Plugin::Database> and L<Dancer2::Plugin::Database> modules.

=head1 METHODS

=head2 database

Implements the C<database> keyword.

=cut

sub database {
    my %args = @_;
    my $arg       = $args{arg}       || undef;
    my $settings  = $args{settings}  || {};
    my $logger    = $args{logger}    || sub {}; ## die?
    my $hook_exec = $args{hook_exec} || sub {}; ## die?

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
        $conn_details = _merge_settings($arg, $settings, $logger);
    } else {
        $handle_key = defined $arg ? $arg : $def_handle;
        $conn_details = _get_settings($arg, $settings, $logger);
        if (!$conn_details) {
            $logger->(error => "No DB settings for " . ($arg || "default connection"));
            return (undef, $settings);
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
        # If we should never check, go no further:
        if (!$conn_details->{connection_check_threshold}) {
            return ($handle->{dbh}, $settings);
        }

        if ($handle->{dbh}{Active} && $conn_details->{connection_check_threshold} &&
            time - $handle->{last_connection_check}
            < $conn_details->{connection_check_threshold}) 
        {
            return ($handle->{dbh}, $settings);
        } else {
            if (_check_connection($handle->{dbh})) {
                $handle->{last_connection_check} = time;
                return ($handle->{dbh}, $settings);
            } else {

                $logger->(debug => "Database connection went away, reconnecting");
                $hook_exec->('database_connection_lost', $handle->{dbh});

                if ($handle->{dbh}) {
                    eval { $handle->{dbh}->disconnect }
                }

                # Need a new handle.
                # Fall through to the new connection codepath to get one.
            }
        }
    }

    # Get a new connection
    $handle->{dbh} = _get_connection($conn_details, $logger, $hook_exec);

    if ($handle->{dbh}) {

        $handle->{last_connection_check} = time;
        $handles{$pid_tid}{$handle_key} = $handle;

        if (ref $handle_key && ref $handle_key ne ref $def_handle) {
            # We were given a hashref of connection settings.  Shove a
            # reference to that hashref into the handle, so that the hashref
            # doesn't go out of scope for the life of the handle.
            # Otherwise, that area of memory could be re-used, and, given
            # different DB settings in a hashref that just happens to have
            # the same address, we'll happily hand back the original handle.
            # See http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=665221
            # Thanks to Sam Kington for suggesting this fix :)
            $handle->{_orig_settings_hashref} = $handle_key;
        }

        return ($handle->{dbh}, $settings);
    } else {
        return (undef, $settings);
    }

}


sub _merge_settings {
    my ($arg, $settings, $logger) = @_;
    $arg->{charset}  = $settings->{charset};

    $arg = _set_defaults($arg);

    return $arg;
}

sub _get_settings {
    my ($name, $settings, $logger) = @_;
    my $return_settings;

    # If no name given, just return the default settings
    if (!defined $name) {
        $return_settings = { %$settings };
        if (!$return_settings->{driver} && !$return_settings->{dsn}) {
            $logger->('error',
                "Asked for default connection (no name given)"
                ." but no default connection details found in config"
            );
        }
    } else {
        # If there are no named connections in the config, bail now:
        return unless exists $settings->{connections};


        # OK, find a matching config for this name:
        if (my $named_settings = $settings->{connections}{$name}) {
            # Take a (shallow) copy of the settings, so we don't change them
            $return_settings = { %$named_settings };
        } else {
            # OK, didn't match anything
            $logger->('error',
                      "Asked for a database handle named '$name' but no matching  "
                      ."connection details found in config"
            );
        }
    }

    $return_settings = _set_defaults($return_settings);

    return $return_settings;
}

sub _set_defaults {
    my $return_settings = shift;
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

    # If the setting wasn't provided, default to 30 seconds; if a false value is
    # provided, though, leave it alone.  (Older versions just checked for
    # truthiness, so a value of zero would still default to 30 seconds, which
    # isn't ideal.)
    if (!exists $return_settings->{connection_check_threshold}) {
        $return_settings->{connection_check_threshold} = 30;
    }

    return $return_settings;
}


# Given the settings to use, try to get a database connection
sub _get_connection {
    my ($settings, $logger, $hook_exec) = @_;

    if (!$settings->{dsn} && !$settings->{driver}) {
        die "Can't get a database connection without settings supplied!\n"
            . "Please check you've supplied settings in config as per the "
            . "Dancer::Plugin::Database documentation";
    }

    # Assemble the DSN:
    my $dsn = '';
    my $driver = '';
    if ($settings->{dsn}) {
        $dsn = $settings->{dsn};
        ($driver) = $dsn =~ m{^dbi:([^:]+)}i;
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

        for (qw(database dbname host port sid server)) {
            if (exists $settings->{$_}) {
                push @extra_args, $_ . "=" . $settings->{$_};
            }
        }
        if (my $even_more_dsn_args = $settings->{dsn_extra}) {
            foreach my $arg ( keys %$even_more_dsn_args ) {
                push @extra_args, $arg . '=' . $even_more_dsn_args->{$arg};
            }
        }
        $dsn .= ':' . join(';', @extra_args) if @extra_args;
    }

    # If the app is configured to use UTF-8, the user will want text from the
    # database in UTF-8 to Just Work, so if we know how to make that happen, do
    # so, unless they've set the auto_utf8 plugin setting to a false value.
    my $app_charset = $settings->{charset} || "";
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
            $logger->(
                debug => "Adding $param to DBI connection params"
                    . " to enable UTF-8 support"
            );
            $settings->{dbi_params}{$param} = 1;
        }
    }

    # To support the database_error hook, use DBI's HandleError option
    $settings->{dbi_params}{HandleError} = sub {
        my ($error, $handle) = @_;
        $hook_exec->('database_error', $error, $handle);
    };

    my $dbh = DBI->connect($dsn,
        $settings->{username}, $settings->{password}, $settings->{dbi_params}
    );

    if (!$dbh) {
        $logger->(error => "Database connection failed - " . $DBI::errstr);
        $hook_exec->('database_connection_failed', $settings);
        return undef;
    } elsif (exists $settings->{on_connect_do}) {
        my $to_do = ref $settings->{on_connect_do} eq 'ARRAY'
            ?   $settings->{on_connect_do}
            : [ $settings->{on_connect_do} ];
        for (@$to_do) {
            $dbh->do($_) or
              $logger->(error => "Failed to perform on-connect command $_");
        }
    }

    $hook_exec->('database_connected', $dbh);

    # Indicate whether queries generated by quick_query() etc in
    # Dancer::Plugin::Database::Core::Handle should be logged or not; this seemed a
    # little dirty, but DBI's docs encourage it
    # ("You can stash private data into DBI handles via $h->{private_..._*}..")
    $dbh->{private_dancer_plugin_database} = {
        log_queries => $settings->{log_queries} || 0,
        logger      => $logger,
    };



    # Re-bless it as a Dancer::Plugin::Database::Core::Handle object, to provide nice
    # extra features (unless the config specifies a different class; if it does,
    # this should be a subclass of Dancer::Plugin::Database::Core::Handle in order to
    # extend the features provided by it, or a direct subclass of DBI::db (or
    # even DBI::db itself) to bypass the features provided by D::P::D::Handle)
    my $handle_class = 
        $settings->{handle_class} || 'Dancer::Plugin::Database::Core::Handle';
    my $package = $handle_class;
    $package =~ s{::}{/}g;
    $package .= '.pm';
    require $package;

    return bless($dbh => $handle_class);
}



# Check the connection is alive
sub _check_connection {
    my $dbh = shift;
    return unless $dbh;
    if ($dbh->{Active}) { 
        my $result = eval { $dbh->ping };

        return 0 if $@;

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


=head1 AUTHOR

David Precious, C<< <davidp at preshweb.co.uk> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-dancer-plugin-database-core at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Dancer-Plugin-Database-Core>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Dancer::Plugin::Database::Core


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Dancer-Plugin-Database-Core>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Dancer-Plugin-Database-Core>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Dancer-Plugin-Database-Core>

=item * Search CPAN

L<http://search.cpan.org/dist/Dancer-Plugin-Database-Core/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2016 David Precious.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, er to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of Dancer::Plugin::Database::Core
