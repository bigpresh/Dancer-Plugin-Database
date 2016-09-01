package Dancer::Plugin::Database::Core::Handle;

use strict;
use Carp;
use DBI;
use base qw(DBI::db);

our $VERSION = '0.16';

=head1 NAME

Dancer::Plugin::Database::Core::Handle - subclassed DBI connection handle

=head1 DESCRIPTION

Subclassed DBI connection handle with added convenience features


=head1 SYNOPSIS

  # in your Dancer app:
  database->quick_insert($tablename, \%data);

  # Updating a record where id = 42:
  database->quick_update($tablename, { id => 42 }, { foo => 'New value' });

  # Fetching a single row quickly in scalar context
  my $employee = database->quick_select('employees', { id => $emp_id });

  # Fetching multiple rows in list context - passing an empty hashref to signify
  # no where clause (i.e. return all rows -  so "select * from $table_name"):
  my @all_employees = database->quick_select('employees', {});

  # count number of male employees
  my $count = database->quick_count('employees', { gender => 'male' });

=head1 Added features

A C<Dancer::Plugin::Database::Handle> object is a subclassed L<DBI::db> L<DBI>
database handle, with the following added convenience methods:

=over 4

=item quick_insert

  database->quick_insert('mytable', { foo => 'Bar', baz => 5 });

Given a table name and a hashref of data (where keys are column names, and the
values are, well, the values), insert a row in the table.

If you need any of the values to be interpolated straight into the SQL, for
instance if you need to use a function call like C<NOW()> or similar, then you
can provide them as a scalarref:

  database->quick_insert('mytable', { foo => 'Bar', timestamp => \'NOW()' });

Of course, if you do that, you must be careful to avoid SQL injection attacks!
=cut

sub quick_insert {
    my ($self, $table_name, $data) = @_;
    return $self->_quick_query('INSERT', $table_name, $data);
}

=item quick_update

  database->quick_update('mytable', { id => 42 }, { foo => 'Baz' });

Given a table name, a hashref describing a where clause and a hashref of
changes, update a row.

As per quick_insert, if you need any of the values to be interpolated straight
in the SQL, for e.g. to use a function call, provide a scalarref:

  database->quick_update('mytable', { id => 42 }, { counter => \'counter + 1' });

Of course, if you do that, you must be careful to avoid SQL injection attacks!

=cut

sub quick_update {
    my ($self, $table_name, $where, $data) = @_;
    return $self->_quick_query('UPDATE', $table_name, $data, $where);
}


=item quick_delete

  database->quick_delete($table, {  id => 42 });

Given a table name and a hashref to describe the rows which should be deleted
(the where clause - see below for further details), delete them.

=cut

sub quick_delete {
    my ($self, $table_name, $where) = @_;
    return $self->_quick_query('DELETE', $table_name, undef, $where);
}


=item quick_select

  my $row  = database->quick_select($table, { id => 42 });
  my @rows = database->quick_select($table, { id => 42 });

Given a table name and a hashref of where clauses (see below for explanation),
and an optional hashref of options, returns either the first matching 
row as a hashref if called in scalar context, or a list of matching rows 
as hashrefs if called in list context.  The third argument is a hashref of
options to allow additional control, as documented below.  For backwards
compatibility, it can also be an arrayref of column names, which acts in the
same way as the C<columns> option.

The options you can provide are:

=over 4

=item C<columns>

An arrayref of column names to return, if you only want certain columns returned

=item C<order_by>

Specify how the results should be ordered.  This option can take various values:

=over 4

=item * a straight scalar or arrayref sorts by the given column(s):

    { order_by => 'foo' }           # equivalent to "ORDER BY foo"
    { order_by => [ qw(foo bar) ] } # equiv to "ORDER BY foo,bar"

=item * a hashref of C<order => column name>, e.g.:

    { order_by => { desc => 'foo' } } # equiv to ORDER BY foo DESC
    { order_by => [ { desc => 'foo' }, { asc => 'bar' } ] }
       # above is equiv to ORDER BY foo DESC, bar ASC

=back

=item C<limit>

Limit how many records will be returned; equivalent to e.g. C<LIMIT 1> in an SQL
query.  If called in scalar context, an implicit LIMIT 1 will be added to the
query anyway, so you needn't add it yourself.

An example of using options to control the results you get back:

    # Get the name & phone number of the 10 highest-paid men:
    database->quick_select(
        'employees', 
        { gender => 'male' },
        { order_by => 'salary', limit => 10, columns => [qw(name phone)] }
    );

=cut

=item C<offset> number

C<Offset> says to skip that many rows before beginning to return rows (postgresql).


Example:

    # Get the name & phone number of the 10 highest-paid men starting from 11th:
    database->quick_select(
        'employees', 
        { gender => 'male' },
        { order_by => 'salary', offset => 10, limit => 10, columns => [qw(name phone)] }
    );


=cut

sub quick_select {
    my ($self, $table_name, $where, $opts) = @_;

    # For backwards compatibility, accept an arrayref of column names as the 3rd
    # arg, instead of an arrayref of options:
    if ($opts && ref $opts eq 'ARRAY') {
        $opts = { columns => $opts };
    }

    # Make sure to call _quick_query in the same context we were called.
    # This is a little ugly, rewrite this perhaps.
    if (wantarray) {
        return ($self->_quick_query('SELECT', $table_name, $opts, $where));
    } else {
        return $self->_quick_query('SELECT', $table_name, $opts, $where);
    }
}

=back

=item quick_lookup

  my $id  = database->quick_lookup($table, { email => $params->{'email'} }, 'userid' );

This is a bit of syntactic sugar when you just want to lookup a specific
field, such as when you're converting an email address to a userid (say
during a login handler.)

This call always returns a single scalar value, not a hashref of the
entire row (or partial row) like most of the other methods in this library. 

Returns undef when there's no matching row or no such field found in 
the results.

=cut

sub quick_lookup {
    my ($self, $table_name, $where, $data) = @_;
    my $opts = { columns => [$data] };
    my $row = $self->_quick_query('SELECT', $table_name, $opts, $where);

    return ( $row && exists $row->{$data} ) ? $row->{$data} : undef;
}

=item quick_count

  my $count = database->quick_count($table,
                                    { email => $params->{'email'} });

This is syntactic sugar to return a count of all rows which match your
parameters, useful for pagination.

This call always returns a single scalar value, not a hashref of the
entire row (or partial row) like most of the other methods in this
library.

=cut

sub quick_count {
    my ($self, $table_name, $where) = @_;
    my $opts = {}; #Options are irrelevant for a count.
    my @row = $self->_quick_query('COUNT', $table_name, $opts, $where);

    return ( @row ) ? $row[0] : undef ;
}

# The 3rd arg, $data, has a different meaning depending on the type of query
# (no, I don't like that much; I may refactor this soon to use named params).
# For INSERT/UPDATE queries, it'll be a hashref of field => value.
# For SELECT queries, it'll be a hashref of additional options.
# For DELETE queries, it's unused.
sub _quick_query {
    my ($self, $type, $table_name, $data, $where) = @_;
    
    # Basic sanity checks first...
    if ($type !~ m{^ (SELECT|INSERT|UPDATE|DELETE|COUNT) $}x) {
        carp "Unrecognised query type $type!";
        return;
    }
    if (!$table_name || ref $table_name) {
        carp "Expected table name as a straight scalar";
        return;
    }
    if (($type eq 'INSERT' || $type eq 'UPDATE')
        && (!$data || ref $data ne 'HASH')) 
    {
        carp "Expected a hashref of changes";
        return;
    }
    if (($type =~ m{^ (SELECT|UPDATE|DELETE|COUNT) $}x)
        && (!$where)) {
        carp "Expected where conditions";
        return;
    }

    # OK, get the SQL we're going to need
    # TODO: can we replace our own generation with e.g. SQL::Abstract?  How much
    # backwards-incompatible change would that incur?
    my ($sql, @bind_params) = $self->_generate_sql(
        $type, $table_name, $data, $where
    );


    # Dancer::Plugin::Database will have looked at the log_queries setting and
    # stashed it away for us to see:
    if ($self->{private_dancer_plugin_database}{log_queries}) {
    	$self->{private_dancer_plugin_database}{logger}->(debug => 
            "Executing $type query $sql with params " . join ',', 
            map {
                defined $_ ? 
                $_ =~ /^[[:ascii:]]+$/ ? 
                    length $_ > 50 ? substr($_, 0, 47) . '...' : $_
                : "[non-ASCII data not logged]" : 'undef'
            } @bind_params
        );
    }

    # Select queries, in scalar context, return the first matching row; in list
    # context, they return a list of matching rows.
    if ($type eq 'SELECT') {
        if (wantarray) {
            return @{ 
                $self->selectall_arrayref(
                    $sql, { Slice => {} }, @bind_params
                )
            };
        } else {
            return $self->selectrow_hashref($sql, undef, @bind_params);
        }

    } elsif ($type eq 'COUNT') {
        return $self->selectrow_array($sql, undef, @bind_params);
    } else {
        # INSERT/UPDATE/DELETE queries just return the result of DBI's do()
        return $self->do($sql, undef, @bind_params);
    }
}

sub _generate_sql {
    my ($self, $type, $table_name, $data, $where) = @_;

    my $which_cols = '*';
    my $opts = $type eq 'SELECT' && $data ? $data : {};
    if ($opts->{columns}) {
        my @cols = (ref $opts->{columns}) 
            ? @{ $opts->{columns} }
            :    $opts->{columns} ;
        $which_cols = join(',', map { $self->_quote_identifier($_) } @cols);
    }

    $table_name = $self->_quote_identifier($table_name);
    my @bind_params;

    my $sql = {
        SELECT => "SELECT $which_cols FROM $table_name",
        INSERT => "INSERT INTO $table_name ",
        UPDATE => "UPDATE $table_name SET ",
        DELETE => "DELETE FROM $table_name ",
        COUNT => "SELECT COUNT(*) FROM $table_name",
    }->{$type};
    if ($type eq 'INSERT') {
        my (@keys, @values);
        for my $key (sort keys %$data) {
            my $value = $data->{$key};
            push @keys, $self->_quote_identifier($key);
            if (ref $value eq 'SCALAR') {
                # If it's a scalarref it goes in the SQL as it is; this is a
                # potential SQL injection risk, but is documented as such - it
                # allows the user to include arbitrary SQL, at their own risk.
                push @values, $$value;
            } else {
                push @values, "?";
                push @bind_params, $value;
            }
        }

        $sql .= sprintf "(%s) VALUES (%s)",
            join(',', @keys), join(',', @values);
    }

    if ($type eq 'UPDATE') {
        my @sql;
        for (sort keys %$data) {
          push @sql, $self->_quote_identifier($_) . '=' .
            (ref $data->{$_} eq 'SCALAR' ? ${$data->{$_}} : "?");
          push @bind_params, $data->{$_} if (ref $data->{$_} ne 'SCALAR');
        }
        $sql .= join ',', @sql;
    }

    if ($type eq 'UPDATE' || $type eq 'DELETE' || $type eq 'SELECT' || $type eq 'COUNT')
    {
        if ($where) {
            my ($where_sql, @where_binds) = $self->generate_where_clauses( $where );
            # Note: it's reasonable to get back no $where_sql in some cases -
            # for e.g. if $where was an empty hashref, to denote "no
            # conditions" - so it's not an error to not get any clauses to add.
            if ($where_sql) {
                $sql .= " WHERE $where_sql";
                push(@bind_params, @where_binds);
            }
        }
    }
    # Add an ORDER BY clause, if we want to:
    if (exists $opts->{order_by} and defined $opts->{order_by}) {
        $sql .= ' ' . $self->_build_order_by_clause($opts->{order_by});
    }


    # Add a LIMIT clause if we want to:
    if (exists $opts->{limit} and defined $opts->{limit}) {
        my $limit = $opts->{limit};
        $limit =~ s/\s+//g;
        # Check the limit clause is sane - just a number, or two numbers with a
        # comma between (if using offset,limit )
        if ($limit =~ m{ ^ \d+ (?: , \d+)? $ }x) {
            # Checked for sanity above so safe to interpolate
            $sql .= " LIMIT $limit";
        } else {
            die "Invalid LIMIT param $opts->{limit} !";
        }
    } elsif ($type eq 'SELECT' && !wantarray) {
        # We're only returning one row in scalar context, so don't ask for any
        # more than that
        $sql .= " LIMIT 1";
    }
    
    if (exists $opts->{offset} and defined $opts->{offset}) {
        my $offset = $opts->{offset};
        $offset =~ s/\s+//g;
        if ($offset =~ /^\d+$/) {
            $sql .= " OFFSET $offset";
        } else {
            die "Invalid OFFSET param $opts->{offset} !";
        }
    }
    return ($sql, @bind_params);
}

sub generate_where_clauses {
    my ($self, $where) = @_;
    my $sql = "";
    my @bind_params;
    if ($where && !ref $where) {
        $sql .= $where;
    } elsif ( ref $where eq 'HASH' ) {
        my @stmts;
        foreach my $k ( sort keys %$where ) {
            my $v = $where->{$k};
            if ( ref $v eq 'HASH' ) {
                my $not = delete $v->{'not'};
                while (my($op,$value) = each %$v ) {
                    my ($cond, $add_bind_param) 
                        = $self->_get_where_sql_clause($op, $not, $value);
                    push @stmts, $self->_quote_identifier($k) . $cond; 
                    push @bind_params, $v->{$op} if $add_bind_param;
                }
            } else {
                my $clause .= $self->_quote_identifier($k);
                if ( ! defined $v ) {
                    $clause .= ' IS NULL';
                }
                elsif ( ! ref $v ) {
                    $clause .= '=?';
                    push @bind_params, $v;
                }
                elsif ( ref $v eq 'ARRAY' ) {
                    $clause .= ' IN (' . (join ',', map { '?' } @$v) . ')';
                    push @bind_params, @$v;
                }
                push @stmts, $clause;
            }
        }
        $sql .= join " AND ", @stmts if keys %$where;
    } elsif (ref $where) {
        carp "Can't handle ref " . ref $where . " for where";
        return;
    }
    return ($sql, @bind_params);
}


sub _get_where_sql_clause {
    my ($self, $op, $not, $value) = @_;

    $op = lc $op;

    # "IS" needs special-casing, as it will be either "IS NULL" or "IS NOT NULL"
    # - there's no need to return a bind param for that.
    if ($op eq 'is') {
        if (defined $value) {
        	$self->{private_dancer_plugin_database}{logger}->(warning => 
                "Using the 'IS' operator only makes sense to test for nullness,"
                ." but a non-undef value was passed.  Did you mean eq/ne?"
            );
        }
        return $not ? 'IS NOT NULL' : 'IS NULL';
    }

    my %st = (
       'ilike'=> ' ILIKE ?',
        'like' => ' LIKE ?',
        'is' => ' IS ?',
        'ge' => ' >= ?',
        'gt' => ' > ?',
        'le' => ' <= ?',
        'lt' => ' < ?',
        'eq' => ' = ?',
        'ne' => ' != ?',
    );

    # Return the appropriate SQL, and indicate that the value should be added to
    # the bind params
    return (($not ? ' NOT' . $st{$op} : $st{$op}), 1);
}

# Given either a column name, or a hashref of e.g. { asc => 'colname' },
# or an arrayref of either, construct an ORDER BY clause (quoting col names)
# e.g.:
# 'foo'              => ORDER BY foo
# { asc => 'foo' }   => ORDER BY foo ASC
# ['foo', 'bar']     => ORDER BY foo, bar
# [ { asc => 'foo' }, { desc => 'bar' } ]
#      => 'ORDER BY foo ASC, bar DESC
sub _build_order_by_clause {
    my ($self, $in) = @_;

    # Input could be a straight scalar, or a hashref, or an arrayref of either
    # straight scalars or hashrefs.  Turn a straight scalar into an arrayref to
    # avoid repeating ourselves.
    $in = [ $in ] unless ref $in eq 'ARRAY';

    # Now, for each of the fields given, add them to the clause
    my @sort_fields;
    for my $field (@$in) {
        if (!ref $field) {
            push @sort_fields, $self->_quote_identifier($field);
        } elsif (ref $field eq 'HASH') {
            my ($order, $name) = %$field;
            $order = uc $order;
            if ($order ne 'ASC' && $order ne 'DESC') {
                die "Invalid sort order $order used in order_by option!";
            }
            # $order has been checked to be 'ASC' or 'DESC' above, so safe to
            # interpolate
            push @sort_fields, $self->_quote_identifier($name) . " $order";
        }
    }

    return "ORDER BY " . join ', ', @sort_fields;
}

# A wrapper around DBI's quote_identifier which first splits on ".", so that
# e.g. database.table gets quoted as `database`.`table`, not `database.table`
sub _quote_identifier {
    my ($self, $identifier) = @_;

    return join '.', map { 
        $self->quote_identifier($_) 
    } split /\./, $identifier;
}

=back

All of the convenience methods provided take care to quote table and column
names using DBI's C<quote_identifier>, and use parameterised queries to avoid
SQL injection attacks.  See L<http://www.bobby-tables.com/> for why this is
important, if you're not familiar with it.


=head1 WHERE clauses as hashrefs

C<quick_update>, C<quick_delete> and C<quick_select> take a hashref of WHERE
clauses.  This is a hashref of field => 'value', each of which will be
included in the WHERE clause used, for instance:

  { id => 42 }

Will result in an SQL query which would include:

  WHERE id = 42

When more than one field => value pair is given, they will be ANDed together:

  { foo => 'Bar', bar => 'Baz' }

Will result in:

  WHERE foo = 'Bar' AND bar = 'Baz'

(Actually, parameterised queries will be used, with placeholders, so SQL
injection attacks will not work, but it's easier to illustrate as though the
values were interpolated directly.  Don't worry, they're not.)

With the same idea in mind, you can check if a value is NULL with:

  { foo => undef }

This will be correctly rewritten to C<foo IS NULL>.

You can pass an empty hashref if you  want all rows, e.g.:

  database->quick_select('mytable', {});

... is the same as C<"SELECT * FROM 'mytable'">

If you pass in an arrayref as the value, you can get a set clause as in the
following example:

 { foo => [ 'bar', 'baz', 'quux' ] } 

... it's the same as C<WHERE foo IN ('bar', 'baz', 'quux')>

If you need additional flexibility, you can build fairly complex where 
clauses by passing a hashref of condition operators and values as the 
value to the column field key.

Currently recognized operators are:

=over

=item 'like'

 { foo => { 'like' => '%bar%' } } 

... same as C<WHERE foo LIKE '%bar%'>

=item 'ilike'

Postgres-specific - same as 'like', but case-insensitive.

=item 'gt' / 'ge'

 'greater than' or 'greater or equal to'
  
 { foo => { 'ge' => '42' } } 

... same as C<WHERE foo E<gt>= '42'>

=item 'lt' / 'le'

 'less than' or 'less or equal to'

 { foo => { 'lt' => '42' } } 

... same as C<WHERE foo E<lt> '42'>

=item 'eq' / 'ne' / 'is'

 'equal' or 'not equal' or 'is'

 { foo => { 'ne' => 'bar' } }

... same as C<WHERE foo != 'bar'>

=back

You can also include a key named 'not' with a true value in the hashref 
which will (attempt) to negate the other operator(s). 

 { foo => { 'like' => '%bar%', 'not' => 1 } }

... same as C<WHERE foo NOT LIKE '%bar%'>

If you use undef as the value for an operator hashref it will be 
replaced with 'NULL' in the query.

If that's not flexible enough, you can pass in your own scalar WHERE clause 
string B<BUT> there's no automatic sanitation on that - if you suffer 
from a SQL injection attack - don't blame me!
Don't forget to use C<quote()>/C<quote_identifier()> on it then.

=head1 AUTHOR

David Precious C< <<davidp@preshweb.co.uk >> >

=head1 ACKNOWLEDGEMENTS

See L<Dancer::Plugin::Database/ACKNOWLEDGEMENTS>

=head1 SEE ALSO

L<Dancer::Plugin::Database> and L<Dancer2::Plugin::Database>

L<Dancer> and L<Dancer2>

L<DBI>

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

1;
__END__
