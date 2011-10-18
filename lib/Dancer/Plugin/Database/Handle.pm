package Dancer::Plugin::Database::Handle;

use strict;
use Carp;
use DBI;
use base qw(DBI::db);

our $VERSION = '0.07';

=head1 NAME

Dancer::Plugin::Database::Handle - subclassed DBI connection handle

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


=head1 Added features

A C<Dancer::Plugin::Database::Handle> object is a subclassed L<DBI::db> L<DBI>
database handle, with the following added convenience methods:

=over 4

=item quick_insert

  database->quick_insert('mytable', { foo => 'Bar', baz => 5 });

Given a table name and a hashref of data (where keys are column names, and the
values are, well, the values), insert a row in the table.

=cut

sub quick_insert {
    my ($self, $table_name, $data) = @_;
    return $self->_quick_query('INSERT', $table_name, $data);
}

=item quick_update

  database->quick_update('mytable', { id => 42 }, { foo => 'Baz' });

Given a table name, a hashref describing a where clause and a hashref of
changes, update a row.

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

  -or-

  my $row  = database->quick_select($table, { id => 42 }, [ 'foo', 'bar' ]);
  my @row  = database->quick_select($table, { id => 42 }, [ 'foo', 'bar' ]);

Given a table name and a hashref of where clauses (see below for explanation),
and an optional list of columns to return, returns either the first matching 
row as a hashref if called in scalar context, or a list of matching rows 
as hashrefs if called in list context.

=cut

sub quick_select {
    my ($self, $table_name, $where, $data) = @_;
    # Make sure to call _quick_query in the same context we were called.
    # This is a little ugly, rewrite this perhaps.
    if (wantarray) {
        return ($self->_quick_query('SELECT', $table_name, $data, $where));
    } else {
        return $self->_quick_query('SELECT', $table_name, $data, $where);
    }
}

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

    my $row = $self->_quick_query('SELECT', $table_name, [$data], $where);

    return ( $row && exists $row->{$data} ) ? $row->{$data} : undef;
}

sub _quick_query {
    my ($self, $type, $table_name, $data, $where) = @_;
    
    if ($type !~ m{^ (SELECT|INSERT|UPDATE|DELETE) $}x) {
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
    if (($type =~ m{^ (SELECT|UPDATE|DELETE) $}x)
        && (!$where)) {
        carp "Expected where conditions";
        return;
    }

    my $select_params = '*';
    if ($type eq 'SELECT' && $data) {
        if (ref $data ne 'ARRAY') {
            carp 'Expected arrayref of data';
            return;
        }
        else {
            $select_params = join(',', map { $self->quote_identifier($_) } @$data);
        }
    }

    $table_name = $self->quote_identifier($table_name);
    my @bind_params;

    my $sql = {
        SELECT => "SELECT $select_params FROM $table_name ",
        INSERT => "INSERT INTO $table_name ",
        UPDATE => "UPDATE $table_name SET ",
        DELETE => "DELETE FROM $table_name ",
    }->{$type};
    if ($type eq 'INSERT') {
        $sql .= "("
            . join(',', map { $self->quote_identifier($_) } keys %$data)
            . ") VALUES ("
            . join(',', map { "?" } values %$data)
            . ")";
        push @bind_params, values %$data;
    }
    if ($type eq 'UPDATE') {
        $sql .= join ',', map { $self->quote_identifier($_) .'=?' } keys %$data;
        push @bind_params, values %$data;
    }

    if ($type eq 'UPDATE' || $type eq 'DELETE' || $type eq 'SELECT') 
    {
        if (!ref $where) {
            $sql .= " WHERE " . $where;
        }
        elsif ( ref $where eq 'HASH' ) {
            my @stmts;
            foreach my $k ( keys %$where ) {
                my $v = $where->{$k};
                if ( ref $v eq 'HASH' ) {
                    my $not = delete $v->{'not'};
                    foreach my $op ( keys %$v ) {
                        push @stmts, $self->quote_identifier($k) . 
                            $self->_get_where_sql($op, $not);
                        push @bind_params, 
                            defined $v->{$op} ? $v->{$op} : 'NULL';
                    }
                }
                else {
                    my $clause .= $self->quote_identifier($k);
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
            $sql .= " WHERE " . join " AND ", @stmts if keys %$where;
        }
        else {
            carp "Can't handle ref " . ref $where . " for where";
            return;
        }
    }

    # If it's a select query and we're called in scalar context, we'll only
    # return one row, so add a LIMIT 1
    if ($type eq 'SELECT' && !wantarray) {
        $sql .= ' LIMIT 1';
    }

    # Dancer::Plugin::Database will have looked at the log_queries setting and
    # stashed it away for us to see:
    if ($self->{private_dancer_plugin_database}{log_queries}) {
        Dancer::Logger::debug(
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

    } else {
        # INSERT/UPDATE/DELETE queries just return the result of DBI's do()
        return $self->do($sql, undef, @bind_params);
    }
}

sub _get_where_sql {
    my ($self, $op, $not) = @_;

    $op = lc $op;

    return ' IS NOT ?' if ( $op eq 'is' && $not );

    my %st = (
        'like' => ' LIKE ?',
        'is' => ' IS ?',
        'ge' => ' >= ?',
        'gt' => ' > ?',
        'le' => ' <= ?',
        'lt' => ' < ?',
        'eq' => ' = ?',
        'ne' => ' != ?',
    );

    return $not ? ' NOT' . $st{$op} : $st{$op};
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

=item 'ge' / 'gt'
 
 'greater than' or 'greater or equal to'
  
 { foo => { 'ge' => '42' } } 

... same as C<WHERE foo >= '42'>

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

=head1 AUTHOR

David Precious C< <<davidp@preshweb.co.uk >> >


=head1 SEE ALSO

L<Dancer::Plugin::Database>

L<Dancer>

L<DBI>

=cut

1;
__END__
