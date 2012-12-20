# Copyright (c) 2012, Mitchell Cooper
package Evented::Database;

use warnings;
use strict;
use v5.10;
use utf8;
use parent 'Evented::Configuration';

use Evented::Configuration;

use Scalar::Util qw(blessed looks_like_number);

our $VERSION = '0.1';

###############################
### CONFIGURATION OVERRIDES ###
###############################

# create a new database instance.
sub new {
    my ($class, %opts) = @_;
    

    # a 'db' option must be present.
    if (!$opts{db}) {
        return error 'no DBI-compatible \'db\' option specified.';
    }
    
    # TODO: ensure that the database object is DBI-compatible.
    
    
    # create the object.
    my $edb = $class->SUPER::new(%opts);
    
    return $edb;
}

# sub parse_config()

# returns true if the block is found.
# supports unnamed blocks by get(block, key)
# supports   named blocks by get([block type, block name], key)
sub has_block {

}

# returns a list of all the names of a block type.
# for example, names_of_block('listen') might return ('0.0.0.0', '127.0.0.1')
sub names_of_block {

}

# returns a list of all the keys in a block.
# for example, keys_of_block('modules') would return an array of every module.
# accepts block type or [block type, block name] as well.
sub keys_of_block {

}

# returns a list of all the values in a block.
# accepts block type or [block type, block name] as well.
sub values_of_block {

}

# returns the key:value hash of a block.
# accepts block type or [block type, block name] as well.
sub hash_of_block {

}

# get a configuration value.
# supports unnamed blocks by get(block, key)
# supports   named blocks by get([block type, block name], key)
sub get {

}

##########################
### DATABASE INTERNALS ###
##########################

# returns the ED string value and type associated with an identifier.
sub _db_get_value {
    my ($edb, $value_id) = @_;
}

# converts an ED string value and type to Perl datatypes.
# for non-scalar values, references are returned.
sub _db_convert_value {
    my ($edb, $value_string, $value_type) = @_;
    given ($value_type) {
    
    # strings are wrapped by double quotes, escaping them if necessary.
    when ('string') {
    
        # if it is not in this format, it is a storage error.
        my $res = $value_string !~ m/^"(.+)"$/;
        if (!$res) {
            return error "value '$value_string' in database is not a valid string";
        }
        
        # remove the escapes.
        # escapes are currently pointless, but they will be needed eventually when
        # an improved parser is introduced to Evented::Database.
        my $inner_string = $1;
        $inner_string =~ s/(\\"|\\\\)//g;
        
        # simple as that; return the string.
        return $inner_string;
        
    }
    
    # numbers are plain integers and floats.
    # note: they may be stored in any valid Perl form: int, float, notated, etc.
    when ('number') {
    
        # first, ensure that the value looks like a number.
        if (!looks_like_number($value_string)) {
            return error "value '$value_string' in database is not a valid number";
        }
        
        # it is, so return it.
        return $value_string;
        
    }
    
    # arrays are comma-separated lists of value identifiers.
    when ('array') {
    
        my @final;
        
        # if this is an empty array, we should not waste our time parsing it.
        if (!$value_string) {
            return \@final;
        }
        
        # it's not empty, so we will split the elements by commas.
        my @ids = split /,/, $value_string;
        
        # iterate through each, insuring that it exists and is valid.
        foreach my $id (@ids) {
            my $val = $edb->_db_get_value($id);
            
            # if it wasn't set, there was an error.
            if (!$val) {
                return error "error in array '$value_string' value identifier '$id'";
            }
            
            push @final, $val;
        }
        
        # return the final array as a reference.
        return \@final;
        
    }
    
    when ('hash') {
    }
    
    }
    return;
}

#####################
### MISCELLANEOUS ###
#####################


# errors.
our $ERROR;
sub error ($) { $ERROR = shift and return }

# remove leading and trailing whitespace.
sub trim {
    my $string = shift;
    $string =~ s/\s+$//;
    $string =~ s/^\s+//;
    return $string;
}

1
