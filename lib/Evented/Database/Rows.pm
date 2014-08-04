# Copyright (c) 2014, Mitchell Cooper
package Evented::Database::Rows;

use warnings;
use strict;
use 5.010;
use utf8;
use parent 'Evented::Object';

sub insert_or_update {
    # match the rows if they exist, update only the things that exists()
    # insert row with all the values if not exists
    # btw this should respect ->row or ->rows for how many to update (1 or all)
    my ($rows, $table, $db, $dbh, @update) = &_args;
    
    # row(s) do exist; update them.
    return $rows->update(@update) if $rows->count;
    
    # otherwise, insert a row.
    # because @update is last, it will override any duplicates in the clause.
    return $table->insert(%{ $rows->{match} }, @update);
    
}

sub select : method { _select(0, @_) }
sub select_hash     { _select(1, @_) }
sub _select {
    # if not wantarray, return the first row's match
    # e.g. table('blah')->rows(haha => 1)->select('hi')
    # two rows match:
    #   if wantarray, return the 'hi' value for each row (@values)
    #   otherwise,    return that value for the first match $values[0]
    
    # e.g. table('blah')->rows(haha => 1)->select('*')
    # two rows match:
    #   if wantarray, return a list of hashrefs of all key:value pairs
    #   otherwise,    return a real hash of key:value pairs for first match
    #
    # I CHANGED MY MIND.
    # THIS IS TOO CONFUSING.
    # just have separate methods
    #
    # ->select           # returns a list of column values for ONE row
    #
    # ->select           # returns a list of array refs of column values for multiple rows
    # with ->rows        # BUT if only one item was specified like select('hi'), it is
                         # just the values, not array refs
    #
    # ->select_hash      # returns a hash of key:value pairs for ONE row
    #                    # if there are args, only include those keys.
    #                    # if no args or if arg '*', include all keys.
    #
    # ->select_hash      # returns a list of hash refs of key:value pairs for multiple rows
    # with ->rows        
    #
    # I MADE ANOTHER DECISION to change
    # ->rows and ->row both represented by same obj type (Rows)
    # but it remembers ->{multiple} or something, changing the behavior of the returns
    my ($hash, $rows, $table, $db, $dbh, @columns) = (shift, &_args);
    @columns = '*' if !@columns;
    
    my $names = join ', ', map { $_ eq '*' ? '*' : "`$_`" } @columns;
    my $query = "SELECT $names FROM `$$table{name}`";
    
    # add clause if applicable.
    my ($clause, @c_bind) = $rows->clause;
    $query .= " $clause" if $clause;
    $query .= " LIMIT 1" if $rows->{single};
    
    # do it.
    my $sth = $dbh->prepare($query) or die $dbh->errstr;
    Evented::Database::_bind($sth, @c_bind);
    $sth->execute;
        
    my $all = $hash ? $sth->fetchall_arrayref({}) : $sth->fetchall_arrayref;
    return unless $all;
    my @ret;
    
    # for a single row, return a real list or hash of column values.
    if ($rows->{single}) {
        @ret = $hash ? %{ $all->[0] || {} } : @{ $all->[0] || [] };
    }
    
    # for multiple rows, return a real list of array or hash references of column values.
    # or, if there is only one specified column, use real array or hash.
    else {
        my $one_column = @columns == 1 && $columns[0] ne '*';
        #@ret = $hash ? %$all : @$all;
        @ret = @$all;
        @ret = map { $_->[0] } @ret if $one_column;
    }
    
    return wantarray ? @ret : $ret[0];
}

sub update {
    my ($rows, $table, $db, $dbh, %update) = &_args;
    my $query = "UPDATE `$$table{name}` SET ";
    my $i = 0;
    foreach my $column (keys %update) {
        my $value = $update{$column};
        $query .= ", " if $i;
        $query .= "`$column` = ?";
        $i++;
    }
    my $sth = $dbh->prepare($query);
    Evented::Database::_bind($sth, values %update);
    $sth->execute;
}

sub clause {
    my $rows  = shift;
    my %match = %{ $rows->{match} || {} };
    return unless scalar keys %match;
    
    my ($i, $clause, @values) = (0, 'WHERE ');
    foreach my $column (keys %match) {
        my $value = $match{$column};
        $clause .= " AND " if $i;
        
        # defined; checking equality.
        if (defined $value) {
            $clause .= "`$column` = ?";
            push @values, $value;
        }
        
        # not defined; checking if null.
        else {
            $clause .= "`$column` IS NULL";
        }
        
        $i++;
    }
    return ($clause, @values);
}

# adds the table and database to argument list.
sub _args {
    my $rows = shift;
    return ($rows, $rows->{table}, $rows->{table}{db}, $rows->{table}{db}{db}, @_);
}

sub count {
    my ($rows, $table, $db, $dbh) = &_args;
    my ($clause, @c_bind) = $rows->clause;
    my $query = "SELECT COUNT(*) FROM `$$table{name}`";
    $query   .= " $clause" if $clause;
    my $sth   = $dbh->prepare($query);
    Evented::Database::_bind($sth, @c_bind);
    $sth->execute;
    return ($sth->fetchrow_array)[0];
}

1