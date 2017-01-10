# Copyright (c) 2012-14, Mitchell Cooper
package Evented::Database;

use warnings;
use strict;
use 5.010;
use utf8;
use parent 'Evented::Configuration';

use Evented::Configuration;
use Scalar::Util qw(blessed looks_like_number);
use JSON::XS ();
use DBI qw(SQL_BLOB SQL_INTEGER SQL_FLOAT SQL_VARCHAR);

sub import {
    my $this_package = shift;
    my $package = caller;
    no strict 'refs';
    *{$package.'::'.$_} = *{$this_package.'::'.$_}
    foreach grep { uc substr($_, 0, 4) eq 'EDB_' } @_;
}

use Evented::Database::Table;
use Evented::Database::Rows;

our $VERSION = '1.15';      # now incrementing by 0.01
our $json    = JSON::XS->new->allow_nonref(1);

sub on  ();
sub off ();
*on  = *Evented::Configuration::on;
*off = *Evented::Configuration::off;

###############################
### CONFIGURATION OVERRIDES ###
###############################

# create a new database instance.
sub new {
    my ($class, %opts) = @_;

    # ensure that the database object is DBI-compatible.
    if (defined $opts{db} and !blessed($opts{db}) || !$opts{db}->isa('DBI::db')) {
        $@ = 'specified \'db\' option is not a valid DBI database.';
        return;
    }

    # create the object.
    my $db = $class->SUPER::new(%opts);

    return $db;
}

# returns true if the block is found.
#
# e.g.  ->has_block('namelessblock')
#       ->has_block(['named', 'block'])
#
sub has_block {
    my ($db, $b_type, $b_name) = &_args;
    return $db->table('configuration')->rows(
        blocktype => $b_type,
        block     => $b_name
    )->count || $db->SUPER::has_block([ $b_type, $b_name ]);
}

# returns a simplified combination of block names (no duplicates).
sub names_of_block {
    my $db = shift;
    my @names1 = $db->_names_of_block(@_);
    my @names2 = $db->SUPER::names_of_block(@_);
    my %h = map { $_ => 1 } @names2, @names1;
    return keys %h;
}

# returns a simlified combination of block hashes.
# no duplicates; database overrides configuration.
sub hash_of_block {
    my $db = shift;
    my %hash1 = $db->_hash_of_block(@_);
    my %hash2 = $db->SUPER::hash_of_block(@_);
    my %hash3 = (%hash2, %hash1);
    return %hash3;
}

# returns a simplified combination of block keys (no duplicates).
sub keys_of_block {
    my $db = shift;
    my @keys1 = $db->_keys_of_block(@_);
    my @keys2 = $db->SUPER::keys_of_block(@_);
    my %h = map { $_ => 1 } @keys1, @keys2;
    return keys %h;
}

# returns a simplified combination of block values.
# if the same pair exists in both, the database overrides.
sub values_of_block {
    my $db = shift;
    my %hash = $db->hash_of_block(@_);
    return values %hash;
}

# get a configuration or simple database value.
# this is a bit more sophisticated than the rest.
sub  get { _get(shift, 0, @_) }
sub _get {
    my ($db, $bool_objs, $block, $key) = (shift, @_);
    my ($b_type, $b_name) = _block($block);
    my $row = $db->table('configuration')->row(
        blocktype => $b_type,
        block     => $b_name,
        key       => $key
    );

    # no rows matched; forward on.
    return $db->SUPER::_get(@_) unless $row->count;

    my $value = $row->select('value');
    return edb_decode($value, $bool_objs);
}

##################################################
### Database versions of configuration methods ###
##################################################

# sub parse_config()
# perhaps we should clear the cache here for the desired rehasing effect.

# returns a list of all the names of a block type.
#
# e.g.  ->names_of_block('listen')
#       returns ('0.0.0.0', '127.0.0.1')
#
sub _names_of_block {
    my ($db, $b_type) = @_;
    my @names = $db->table('configuration')->rows(blocktype => $b_type)->select('block');
    my %h = map { $_ => 1 } @names;
    return keys %h;
    #|| $db->SUPER::names_of_block(@_);
}

# returns the key:value hash (not ref) of a block.
sub _hash_of_block {
    my ($db, $b_type, $b_name) = &_args;
    my @rows = $db->table('configuration')->rows(
        blocktype => $b_type,
        block     => $b_name
    )->select_hash;
    return map { $_->{key} => edb_decode($_->{value}) } @rows;
}

# returns a list of all the keys in a block.
#
# e.g.  ->keys_of_block('modules')
#       returns an array of every module
#
sub _keys_of_block {
    my ($db, $b_type, $b_name) = &_args;
    return $db->table('configuration')->rows(
        blocktype => $b_type,
        block     => $b_name
    )->select('key');
}

############################
## DATABASE-ONLY METHODS ###
############################

# set a simple database value.
#
# e.g.  ->store('cookies', favorite => 'chocolate chip')
#       ->store(['cookies', 'chocolate'], chips => 'yes')
#
sub store {
    my ($db, $b_type, $b_name, $key, $value) = &_args;
    my $old = $db->get([ $b_type, $b_name ], $key);

    # update it.
    my $res = $db->table('configuration')->row(
        blocktype => $b_type,
        block     => $b_name,
        key       => $key
    )->insert_or_update(value => edb_encode($value));

    # fire events.
    my @events = $db->_get_events($b_type, $b_name, $key, $old, $value);
    $db->fire_events_together(@events) if @events;

    return $res;
}

# return a table object.
sub table {
    my ($db, $table_name) = @_;
    return Evented::Database::Table->new(db => $db, name => $table_name);
}

sub write_conf_to_db {
    my $db = shift;
    foreach my $b_type (keys %{ $db->{conf}                     }) {
    foreach my $b_name (keys %{ $db->{conf}{$b_type}            }) {
    foreach my $key    (keys %{ $db->{conf}{$b_type}{$b_name}   }) {
        my $value = $db->{conf}{$b_type}{$b_name}{$key};
        $db->store([ $b_type, $b_name ], $key => $value);
    }}}
}

sub create_tables_maybe {
    my $db = shift;
    $db->table('configuration')->create_or_alter(
        blocktype => 'TEXT',
        block     => 'TEXT',
        key       => 'TEXT',
        value     => 'TEXT'
    );
    $db->table('edb_table_metadata')->create_or_alter(
        table     => 'TEXT',
        key       => 'TEXT',
        value     => 'TEXT'
    );
}

#####################
### MISCELLANEOUS ###
#####################

# errors.
sub error {
    my ($db, $reason) = @_;

    # if $reason is set, we're returning undefined and setting the error.
    if (defined $reason) {
        $db->{EDB_ERROR} = $reason;
        return;
    }

    # otherwise, we're returning the last error set.
    return $db->{EDB_ERROR};

}

sub edb_bind {
    my ($sth, @bind) = @_;
    return unless $sth;
    my $i = 1;
    foreach my $bind (@bind) {
        my @args = $i;

        # data type specified.
        if (blessed $bind && $bind->isa('Evented::Database::DataType')) {
            push @args, $bind->[1];
            push @args, $bind->[0];
        }

        # no type specified.
        else {
            push @args, $bind;
        }

        $sth->bind_param(@args);
        $i++;
    }

    return $sth;
}

sub _args {
    my ($db, $block) = (shift, shift);
    my @a = ($db, _block($block), @_);
    return @a;
}

sub _block {
    my $block = shift;
    return (ref $block && ref $block eq 'ARRAY' ? @$block : ('section', $block));
}

sub edb_encode {
    my $value = shift;

    # convert E::C booleans to JSON::XS
    if (blessed $value && $value->isa('Evented::Configuration::Boolean')) {
        $value = $$value ? \1 : \0;
    }

    # try to encode
    my $res = eval { $json->encode($value) };
    $@ = "edb_encode($value) error: $@" if $@;

    return $res;
}

sub edb_decode {
    my ($value, $bool_objs) = @_;
    return undef if !length $value;

    # try to decode
    my $res = eval { $value = $json->decode($value) };
    $@ = "edb_decode($value) error: $@" if $@;

    # convert JSON::XS booleans to Perl
    if (blessed $res && $res->isa('JSON::XS::Boolean')) {
        return $$res ? on : off     if $bool_objs;
        return $$res ? 1  : undef;
    }

    return $res;
}

sub EDB_STRING  { bless [SQL_VARCHAR, shift], 'Evented::Database::DataType' }
sub EDB_INTEGER { bless [SQL_INTEGER, shift], 'Evented::Database::DataType' }
sub EDB_FLOAT   { bless [SQL_FLOAT,   shift], 'Evented::Database::DataType' }
sub EDB_BLOB    { bless [SQL_BLOB,    shift], 'Evented::Database::DataType' }

1
