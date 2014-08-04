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

use Evented::Database::Table;
use Evented::Database::Rows;

our $VERSION = '1.00';
our $json    = JSON::XS->new->allow_nonref(1);

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

# sub parse_config()
# perhaps we should clear the cache here for the desired rehasing effect.

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
    )->count || $db->SUPER::has_block(@_);
}

# returns a list of all the names of a block type.
#
# e.g.  ->names_of_block('listen')
#       returns ('0.0.0.0', '127.0.0.1')
#
sub names_of_block {
    my ($db, $b_type) = @_;
    my @names = $db->table('configuration')->rows(blocktype => $b_type)->select('block');
    my %h = map { $_ => 1 } @names;
    return keys %h;
    #|| $db->SUPER::names_of_block(@_);
}

# returns the key:value hash (not ref) of a block.
sub hash_of_block {
    my ($db, $b_type, $b_name) = &_args;
    my @rows = $db->table('configuration')->rows(
        blocktype => $b_type,
        block     => $b_name
    )->select_hash;
    return map { $_->{key} => $json->decode($_->{value}) } @rows;
}

# returns a list of all the keys in a block.
#
# e.g.  ->keys_of_block('modules')
#       returns an array of every module
#
sub keys_of_block {
    my ($db, $b_type, $b_name) = &_args;
    return $db->table('configuration')->rows(
        blocktype => $b_type,
        block     => $b_name
    )->select('key');
}

# returns a list of all the values in a block.
sub values_of_block {
    my ($db, $b_type, $b_name) = &_args;
    my $value = $db->table('configuration')->rows(
        blocktype => $b_type,
        block     => $b_name
    )->select('value');
    return defined $value ? $json->decode($value) : $db->SUPER::values_of_block(@_);
}

# get a configuration or simple database value.
sub get {
    my ($db, $b_type, $b_name, $key) = &_args;
    my $value = $db->table('configuration')->row(
        blocktype => $b_type,
        block     => $b_name,
        key       => $key
    )->select('value');
    my $t = defined $value ? $json->decode($value) : $db->SUPER::get(@_);
    return $t;
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
    $db->table('configuration')->row(
        blocktype => $b_type,
        block     => $b_name,
        key       => $key
    )->insert_or_update(value => $json->encode($value));
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
        $db->table('configuration')->row(
            blocktype => $b_type,
            block     => $b_name,
            key       => $key
        )->insert_or_update(value => $json->encode($value));
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
}

#####################
### MISCELLANEOUS ###
#####################

sub _block {
    my $block = shift;
    return (ref $block && ref $block eq 'ARRAY' ? @$block : ('section', $block));
}

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

sub _bind {
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

package Evented::Database::DataType;

1
