package Dancer::Plugin::Database::Handle;

use Carp;
use DBI;
use base qw(DBI::db);


=head1 NAME

Dancer::Plugin::Database::Handle

=head1 DESCRIPTION

Subclassed DBI connection handle with added features


=head1 SYNOPSIS

  # in your Dancer app:
  database->quick_insert($tablename, \%data);

  # Updating a record where id = 42:
  database->quick_update($tablename, { id => 42 }, { foo => 'New value' });


=head1 Added features

A C<Dancer::Plugin::Database::Handle> object is a subclassed L<DBI::st> L<DBI>
database handle, with the following added convenience methods:

=over 4

=item quick_insert

  database->quick_insert('mytable', { foo => 'Bar', baz => 5 });

Given a table name and a hashref of data (where keys are column names, and the
values are, well, the values), insert a row in the table.

=cut

sub quick_insert {
    my ($self, $table_name, $data) = @_;
    if (!$table_name || ref $table_name) {
        carp "Expected table name as a straight scalar";
        return;
    }
    if (!$data || ref $data ne 'HASH') {
        carp "Expected hashref of data";
        return;
    }
    # Quote the table name, no SQL injection here thank you:
    $tablename = $self->quote_identifier($tablename);
    my $field_list = join ',', map { $self->quote($_) } keys %$data;
    my $placeholders = join ',', map { "?" } values %$data;
    my $sql = "INSERT INTO $table_name ($field_list) VALUES($placeholders)";
    Dancer::Logger::debug(
        "Executing query $sql with params: " . join ',', values %$data
    );
    return $self->do($sql, undef, values %$data);

}

=item quick_update

  database->quick_update('mytable', { id => 42 }, { foo => 'Baz' });

Given a table name, a hashref describing a where clause and a hashref of
changes, update a row.

The second parameter is a hashref of field => 'value', each of which will be
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
values were interpolated directly.)

=cut

sub quick_update {
    my ($self, $table_name, $where, $data) = @_;
    
    if (!$table_name || ref $table_name) {
        carp "Expected table name as a straight scalar";
        return;
    }
    if (!$where || ref $where ne 'HASH') {
        carp "Expected a hashref of where conditions";
        return;
    }
    if (!$data || ref $where ne 'HASH') {
        carp "Expected a hashref of changes";
        return;
    }
    $table_name = $self->quote_identifier($table_name);
    my $changes = join ',', 
        map { $self->quote_identifier($_) . '=?' } keys %$data;
    my $where_cond = join ',', 
        map { $self->quote_identifier($_) . '=?' } keys %$where;
    my $sql = "UPDATE $table_name SET $changes WHERE $where_cond";
    Dancer::Logger::debug("Executing query: $sql with params: " 
        . join ',', values %$data, values %$where);
    return $self->do($sql, undef, values %$data, values %$where);
}


=back


=head1 AUTHOR

David Precious C< <<davidp@preshweb.co.uk >> >


=head1 SEE ALSO

L<Dancer::Plugin::Database>

L<Dancer>

L<DBI>

=cut

1;
__END__
