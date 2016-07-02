# Copyright (c) 2014, Mitchell Cooper
package Evented::Database::Table;

use warnings;
use strict;
use 5.010;
use utf8;
use parent 'Evented::Object';
use Evented::Database qw(edb_bind edb_encode);

our $VERSION = '1.11';

sub create_or_alter {
    # create table if not exists
    # add missing columns
    my ($table, @cols_types) = @_;
    return $table->exists ? $table->alter(@cols_types) : $table->create(@cols_types);
}

sub create {
    # must use an array to preserve the order.
    my ($table, $db, $dbh, @cols_types) = &_args;

    # trying to create a table with no columns?
    if (!@cols_types) {
        warn 'Attempting to create table ', $table->{name}, 'with no columns';
        return;
    }

    my $query = "CREATE TABLE `$$table{name}` (";
    my $i = 0;
    while (my ($col, $type) = splice @cols_types, 0, 2) {
        $query .= ', ' if $i;
        $query .= "`$col` $type";
        $i++;
    }
    $query .= ')';

    # something went wrong?
    my $res = $dbh->do($query);
    if (!defined $res) {
        warn "Error in create [$query]: ", $dbh->errstr;
    }

    return $res;
}

# update table layout only if it has changed.
sub alter {
    my ($table, $db, $dbh, @cols_types) = &_args;
    my @desired_cols_types = @cols_types;

    # figure the new columns.
    my (@n_columns, %n_columns);
    while (my ($col, $type) = splice @cols_types, 0, 2) {
        push @n_columns, "`$col` $type";
        $n_columns{$col} = $type;
    }
    my $new_columns = join '|', @n_columns;

    # figure the old columns.
    my $sth = $dbh->prepare("PRAGMA table_info('$$table{name}')");
    $sth->execute;
    my (@o_columns, %o_columns);
    while (my $col = $sth->fetchrow_hashref) {
        $o_columns[ $col->{cid} ] = "`$$col{name}` $$col{type}";
        $o_columns{ $col->{name} } = $col->{type};
    }
    my $old_columns = join '|', @o_columns;

    # the table has not changed.
    return 1 if $new_columns eq $old_columns;

    my $old = $table->{name};
    my $new = "edb_new_$$table{name}";

    # create the new table.
    $db->table($new)->create(@desired_cols_types);

    # insert the old values for columns that still exist.
    my @insert = grep { exists $n_columns{$_} } keys %o_columns;
    my $insert = join ', ', map { "`$_`" } @insert;

    # nothing to insert?
    if (!length $insert) {
        warn "Altering table with nothing to insert? ($old_columns)->($new_columns)\n";
        return;
    }

    my $query  = "INSERT INTO `$new` ($insert) SELECT $insert FROM `$old`";

    # commit these changes.
    $dbh->do($query)                and
    $dbh->do("DROP TABLE `$old`")   and
    $dbh->do("ALTER TABLE `$new` RENAME TO `$old`");

}

sub exists : method {
    # SELECT count(*) FROM sqlite_master WHERE type='table' AND name='table_name';
    my ($table, $db, $dbh) = &_args;
    my $query = "SELECT count(*) FROM sqlite_master "
              . "WHERE `type` = 'table' AND `name` = '$$table{name}'";
    my $sth = $dbh->prepare($query);
    $sth->execute;
    return ($sth->fetchrow_array)[0];
}

sub insert {
    # $db->table('a')->insert(
    #   a => 'b',
    #   b => 'c'
    # );
    my ($table, $db, $dbh, %cols_vals) = &_args;
    my ($i, @values) = 0;
    my ($type_str, $value_str) = ('', '');
    foreach my $column (keys %cols_vals) {
        my $value = $cols_vals{$column};
        if ($i) {
            $type_str  .= ', ';
            $value_str .= ', ';
        }
        $type_str  .= "`$column`";
        $value_str .= '?';
        push @values, $value;
        $i++;
    }
    my $query = "INSERT INTO `$$table{name}` ($type_str) VALUES($value_str)";
    my $sth   = $dbh->prepare($query);
    edb_bind($sth, @values);
    $sth->execute;
}

sub row {
    my $rows = shift->rows(@_);
    $rows->{single} = 1;
    return $rows;
}

sub rows {
    my ($table, %match) = @_;
    return Evented::Database::Rows->new(
        db    => $table->{db},
        table => $table,
        match => \%match
    );
}

# fetch table metadata.
sub meta {
    my ($table, $db, $dbh, $key) = &_args;
    my $value = $db->table('edb_table_metadata')->row(
        table => $table->{name},
        key   => $key
    )->select('value');
    return $value unless $value;
    return $Evented::Database::json->decode($value);
}

# set table metadata.
sub set_meta {
    my ($table, $db, $dbh, $key, $value) = &_args;
    $db->table('edb_table_metadata')->row(
        table => $table->{name},
        key   => $key
    )->insert_or_update(value => edb_encode($value));
}

# adds the database to argument list.
sub _args {
    my $table = shift;
    return ($table, $table->{db}, $table->{db}{db}, @_);
}


1
