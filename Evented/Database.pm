# Copyright (c) 2012-14, Mitchell Cooper
package Evented::Database;

use warnings;
use strict;
use v5.10;
use utf8;
use parent 'Evented::Configuration';

use Evented::Configuration;

use Scalar::Util qw(blessed looks_like_number);

our $VERSION = '0.91';

# Caching
# -----------------------------
#
# Evented::Database caches database values. Although some would argue that this is often
# unnecessary and potentially wasteful of RAM, it is crucial to Evented::Database due to
# fact that Evented::Database is required to parse each EO data string. Regex matches can
# be expensive, and it appears that caching these values in memory is the best option for
# optimal efficiency and minimal processing usage.
#
# Caches are stored in $edb->{cache}. They are stored as hash pairs in the form of
# (block_type:block_name):key. For example, a blocked name 'chocolate' of type 'cookies'
# would store its 'chips' key in $ebd->{cache}{'cookies:chocolate'}{chips}. These values
# are parsed Perl data, not EO data strings. Non-scalar data values (arrays and hashes)
# are represented as scalar references.
#

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
    my $edb = $class->SUPER::new(%opts);
    
    return $edb;
}

# sub parse_config()
# perhaps we should clear the cache here for the desired rehasing effect.

# returns true if the block is found.
# supports unnamed blocks by get(block, key)
# supports   named blocks by get([block type, block name], key)
# checks cache, 
sub has_block {
    my ($edb, $block, $db_only) = @_;
    my ($block_type, $block_name) = ('section', $block);
    
    # no database.
    return if !$edb->{db} && $db_only;
    return $edb->SUPER::has_block($block) if !$edb->{db};
    
    # if $block is an array reference, it's (type, name).
    if (defined ref $block && ref $block eq 'ARRAY') {
        ($block_type, $block_name) = @$block;
    }
    
    # first, check cache.
    if ($edb->{cache}{$block_type.q(:).$block_name}) {
        return 1;
    }

    # check database for block.
    return 1 if ($edb->{db}->do(
        'SELECT block FROM locations WHERE block=? AND blockname=?',
        undef, $block_type, $block_name
    ) + 0);

    # pass it on to Evented::Configuration.    
    return $edb->SUPER::has_block($block) unless $db_only;
    
    return;
}

# returns a list of all the names of a block type.
# for example, names_of_block('listen') might return ('0.0.0.0', '127.0.0.1')
sub names_of_block {
    my ($edb, $block_type, $db_only) = @_;
    my @names;
    
    # no database.
    return @names if !$edb->{db} && $db_only;
    return $edb->SUPER::names_of_block($block_type) if !$edb->{db};
    
    # fetch all 'blockname' values.
    my $sth = $edb->{db}->prepare('SELECT blockname FROM locations WHERE block=?');
    
    # query it.
    my $rv = $sth->execute($block_type);
    
    # add each name we haven't added already.
    while (my $aryref = $sth->fetchrow_arrayref) {
        my $name = $aryref->[0];
        push @names, $name if !($name ~~ @names);
    }
    
    # return the list of names as a pure array.
    return @names if scalar @names;
    
    # pass it on to Evented::Configuration.
    return $edb->SUPER::names_of_block($block_type) unless $db_only;
    
    return @names;
}

# returns a list of all the keys in a block.
# for example, keys_of_block('modules') would return an array of every module.
# accepts block type or [block type, block name] as well.
sub keys_of_block {
    my ($edb, $block, $db_only) = @_;
    my ($block_type, $block_name) = ('section', $block);
    
    my @keys;
    
    # no database.
    return @keys if !$edb->{db} && $db_only;
    return $edb->SUPER::keys_of_block($block) if !$edb->{db};
    
    # if $block is an array reference, it's (type, name).
    if (defined ref $block && ref $block eq 'ARRAY') {
        ($block_type, $block_name) = @$block;
    }
    
    # fetch all 'dkey' values for this block.
    my $sth = $edb->{db}->prepare('SELECT dkey FROM locations WHERE block=? AND blockname=?');
    
    # query it.
    my $rv = $sth->execute($block_type, $block_name);
    
    # add each key we haven't added already.
    while (my $aryref = $sth->fetchrow_arrayref) {
        my $key = $aryref->[0];
        push @keys, $key if !($key ~~ @keys);
    }
    
    # return the list of names as a pure array.
    return @keys if scalar @keys;
    
    # pass it on to Evented::Configuration.
    return $edb->SUPER::keys_of_block($block) unless $db_only;
    
    return @keys;
}

# returns the key:value hash of a block.
# accepts block type or [block type, block name] as well.
sub hash_of_block {
    my ($edb, $block, $db_only) = @_;
    my ($block_type, $block_name) = ('section', $block);
    
    # values are stored as key:value.
    my %values;
    
    # no database.
    return %values if !$edb->{db} && $db_only;
    return $edb->SUPER::hash_of_block($block) if !$edb->{db};
    
    # if $block is an array reference, it's (type, name).
    if (defined ref $block && ref $block eq 'ARRAY') {
        ($block_type, $block_name) = @$block;
    }
    
    # iterate through each key of the block.
    foreach my $key ($edb->keys_of_block([$block_type, $block_name], 1)) {

        # find the value.
        my $value = $edb->_db_get([$block_type, $block_name], $key);
        
        # if there is no value, we have an error.
        if (!defined $value) {
            return $edb->error("could not get value for '$key' key: $$edb{EDB_ERROR}");
        }
        
        # set it in our hash if we haven't already.
        $values{$key} = $value if !defined $values{$key};
        
    }
    
    # return as a pure hash.
    return %values if scalar %values;
    
    # pass it on to Evented::Configuration.
    return $edb->SUPER::hash_of_block($block) unless $db_only;
    
    return %values;
}

# returns a list of all the values in a block.
# accepts block type or [block type, block name] as well.
sub values_of_block {
    my ($edb, $block, $db_only) = @_;
    my ($block_type, $block_name) = ('section', $block);
    
    # no database.
    return () if !$edb->{db} && $db_only;
    return $edb->SUPER::values_of_block($block) if !$edb->{db};
    
    # if $block is an array reference, it's (type, name).
    if (defined ref $block && ref $block eq 'ARRAY') {
        ($block_type, $block_name) = @$block;
    }
    
    # values are stored as key:value.
    my %values = $edb->hash_of_block([$block_type, $block_name], 1);

    # return as a pure hash.
    return values %values if scalar %values;
    
    # pass it on to Evented::Configuration.
    return $edb->SUPER::values_of_block($block) unless $db_only;
    
    return ();
}

# get a configuration value.
# supports unnamed blocks by get(block, key)
# supports   named blocks by get([block type, block name], key)
sub get {
    my ($edb, $block, $key, $db_only) = @_;
    my ($block_type, $block_name) = ('section', $block);
    
    # no database.
    return if !$edb->{db} && $db_only;
    $edb->SUPER::get($block, $key) if !$edb->{db};
    
    # if $block is an array reference, it's (type, name).
    if (defined ref $block && ref $block eq 'ARRAY') {
        ($block_type, $block_name) = @$block;
    }
    
    # first, check for cached or database value.
    # note: _db_get() always returns Perl values.
    if (defined( my $value = $edb->_db_get([$block_type, $block_name], $key) )) {
        return $value;
    }
    
    # not in database. we will pass this on to Evented::Configuration.
    return $edb->SUPER::get($block, $key) unless $db_only;
    
    return;
}

##############################
## DATABASE PUBLIC METHODS ###
##############################

# creates tables if they have not been created already.
sub create_tables_maybe {
    my $edb = shift;
    
    # no database.
    return unless $edb->{db};
        
    # create locations table.
    $edb->{db}{RaiseError} = 1;
    my $exists = eval { $edb->{db}->do('SELECT block FROM locations LIMIT 1'); 1 };
    $edb->{db}->do('CREATE TABLE locations (
        block       VARCHAR(300),
        blockname   VARCHAR(300),
        dkey        VARCHAR(300),
        valueid     INT
    )') if !$exists;
   
    # create dvalues table.
    $edb->{db}{RaiseError} = 1;
    $exists = eval { $edb->{db}->do('SELECT valueid FROM dvalues LIMIT 1'); 1 };
    $edb->{db}->do('CREATE TABLE dvalues (
        valueid     INT,
        valuetype   VARCHAR(255),
        value       TEXT
    )') if !$exists;
        
    $edb->{db}{RaiseError} = undef;
    return 1;
}

# set a value.
# accepts block type or [block type, block name] as well.
# Example: $edb->store(['cookies', 'chocolate'], mykey => $value)
sub store {
    my ($edb, $block, $key, $value) = @_;
    my ($block_type, $block_name) = ('section', $block);
    return unless $edb->{db};
   
    # if $block is an array reference, it's (type, name).
    if (defined ref $block && ref $block eq 'ARRAY') {
        ($block_type, $block_name) = @$block;
    }
    
    my $block_key = $block_type.q(:).$block_name;
    
    # TODO: if it already exists, overwrite.

    return $edb->_db_store_value(undef, $block_type, $block_name, $block_key, $key, $value);
}

##########################
### DATABASE INTERNALS ###
##########################

# accepts only ([block type, block name], key)
# internal use only: returns cache value if found, database value, undef.
# all values are Perl values, not ED strings.
# any values fetched from the database are cached here.
sub _db_get {
    my ($edb, $block_type, $block_name, $key) = (shift, @{shift()}, shift);

    # no database.
    return unless $edb->{db};

    # first, check for a cached value.
    my $block_key = $block_type.q(:).$block_name;
    if (defined $edb->{cache}{$block_key}{$key}) {
        return $edb->{cache}{$block_key}{$key};
    }
    
    # not cached. let's look in the database.

    # find the location of the value.
    my $value_id = $edb->_db_get_location([$block_type, $block_name], $key);

    # no value identifier found.
    if (!defined $value_id) {
        return $edb->error('no value found');
    }
    
    # we found something, so let's look up the ED value string.
    my ($ed_value, $ed_type) = $edb->_db_get_value($value_id);

    # nothing found.
    if (!defined $ed_value) {
        return $edb->error('strange database error: location found for a null value');
    }
    
    # okay, let's convert the value to Perl and cache it for later.
    my $value = $edb->{cache}{$block_key}{$key} = $edb->_db_convert_value($ed_value, $ed_type);
    
    # if $value is undefined, there was a parse.
    if (!defined $value) {
        return $edb->error("parse error: $$edb{EDB_ERROR}");
    }
    
    # return the pure Perl value.
    # note: non-scalars are returned as references.
    return $value;
    
}

# accepts only ([block type, block name], key)
# returns a value identifier of the given block and key.
# returns undef if nothing is found.
sub _db_get_location {
    my ($edb, $block_type, $block_name, $key) = (shift, @{shift()}, shift);

    # no database.
    return unless $edb->{db};
    
    # prepare the statement.
    my $sth = $edb->{db}->prepare('SELECT valueid FROM locations WHERE block=? AND blockname=? AND dkey=?');
    
    # execute it.
    my $rv = $sth->execute($block_type, $block_name, $key);
    
    # an error occured.
    if (!$rv) {
        return $edb->error('location fetch error: '.$sth->errstr);
    }
    
    # find the value. there should really only be one.
    while (my $aryref = $sth->fetchrow_arrayref) {
        return $aryref->[0];
    }
    
    # nothing was found.
    return;
    
}

# returns the ED string value and type associated with an identifier.
# this does not take any caching into account.
sub _db_get_value {
    my ($edb, $value_id) = @_;
    
    # no database.
    return unless $edb->{db};
    
    # prepare the statement.
    my $sth = $edb->{db}->prepare('SELECT value, valuetype FROM dvalues WHERE valueid=?');
    
    # execute it.
    my $rv = $sth->execute($value_id);
    
    # an error occured.
    if (!$rv) {
        return $edb->error('value fetch error: '.$sth->errstr);
    }
    
    # find the value. there should really only be one.
    while (my $aryref = $sth->fetchrow_arrayref) {
        return wantarray ? ($aryref->[0], $aryref->[1]) : $aryref->[0];
    }
    
    # nothing was found.
    return;
}

# converts an ED string value and type to Perl datatypes.
# for non-scalar values, references are returned.
sub _db_convert_value {
    my ($edb, $value_string, $value_type) = @_;
    return unless defined $value_string;
    given ($value_type) {
    
    # strings are wrapped by double quotes, escaping them if necessary.
    when ('string') {
    
        # if it is not in this format, it is a storage error.
        my $res = $value_string =~ m/^"(.+)"$/;
        if (!$res) {
            return $edb->error("value '$value_string' in database is not a valid string");
        }
        
        # remove the escapes.
        # escapes are currently pointless, but they will be needed eventually when
        # an improved parser is introduced to Evented::Database.
        my $inner_string = $1;
        $inner_string =~ s/\\(")|\\(\\)/$1/g;
        
        # simple as that; return the string.
        return $inner_string;
        
    }
    
    # numbers are plain integers and floats.
    # note: they may be stored in any valid Perl form: int, float, notated, etc.
    when ('number') {
    
        # first, ensure that the value looks like a number.
        if (!looks_like_number($value_string)) {
            return $edb->error("value '$value_string' in database is not a valid number");
        }
        
        # it is, so return it.
        return $value_string + 0;
        
    }
    
    # arrays are comma-separated lists of value identifiers.
    when ('array') {
    
        my @final;
        
        # if this is an empty array, we should not waste our time parsing it.
        if (!length $value_string) {
            return \@final;
        }
        
        # it's not empty, so we will split the elements by commas.
        my @ids = split /,/, $value_string;
        
        # iterate through each, insuring that it exists and is valid.
        foreach my $id (@ids) {
        
            # ensure that the value identifier has length.
            if (!length $id) {
                return $edb->error("syntax error in value ID '$id'");
            }
        
            my $val = $edb->_db_convert_value($edb->_db_get_value($id));
            
            # if it wasn't set, there was an error.
            if (!$val) {
                return $edb->error("error in array '$value_string' value identifier '$id'");
            }
            
            push @final, $val;
        }
        
        # return the final array as a reference.
        return \@final;
        
    }
    
    # hashes are stored as comma-separated pairs of key:value_identifier.
    # FIXME: this is very bad. it needs to interpret escapes in case there are
    # commas or colons in the hash key.
    when ('hash') {
        my %final;
        
        # if this is an empty hash, we should not waste our time parsing it.
        if (!length $value_string) {
            return \%final;
        }
        
        # it's not empty, so we will split the pairs by commas.
        my @pairs = split /,/, $value_string;
        
        # iterate through each pair, insuring that it is valid and the value exists.
        foreach my $pair (@pairs) {
        
            # extract key and value identifiers.
            my ($key, $value_id) = split /:/, $pair;
        
            # if either is undefined or of zero length, we have a problem.
            if (!defined $key || !length $key || !defined $value_id || !length $value_id) {
                return $edb->error("syntax error in hash pair '$pair'");
            }
            
            my $val = $edb->_db_convert_value($edb->_db_get_value($value_id));
            
            # if it wasn't set, there was an error.
            if (!$val) {
                return $edb->error("error in array '$value_string' value identifier '$value_id'");
            }
            
            $final{$key} = $val;
        }
    
        # return the final hash as a reference.
        return \%final;
        
    }
    
    }
    return;
}

# returns the next available ID.
sub _db_next_id {
    my $edb = shift;
    my $sth = $edb->{db}->prepare('SELECT MAX(valueid) FROM dvalues');
    $sth->execute;
    return $sth->fetch->[0] + 1;
}

# store a value in the dvalues table.
# if block information is provided, also inserts that in the location table.
sub _db_store_value {
    my ($edb, $valueid, $block_type, $block_name, $block_key, $key, $value) = @_;

    # get next value id.
    $valueid ||= $edb->_db_next_id;
    
    my $insert = sub {
        my ($type, $value, $real_value) = @_;
        
        # insert the value.
        my $sth1 = $edb->{db}->prepare(
            'INSERT INTO dvalues (valueid, valuetype, value) ' .
            'VALUES (?, ?, ?)'
        );
        $sth1->execute($valueid, $type, $value); # TODO: err handle
        
        # insert the location if necessary.
        if (defined $block_key && defined $key) {
            my $sth2 = $edb->{db}->prepare(
                'INSERT INTO locations (block, blockname, dkey, valueid) ' .
                'VALUES (?, ?, ?, ?)'
            );
            $sth2->execute($block_type, $block_name, $key, $valueid);
            $edb->{cache}{$block_key}{$key} = $real_value;
        }

    };
    
    # string or number.
    if (!ref $value) {
    
        # it's a number.
        if (looks_like_number($value)) {
        
            # force numeric interpretation.
            $value += 0;
            
            # insert.
            $insert->('number', $value, $value);
            
            return 1;
        }
        
        # it's a string.
        my $string_value = $value;
        $string_value =~ s/"/\\"/g;
        $string_value = qq("$string_value");
        
        # insert.
        $insert->('string', $string_value, $value);
        
        return 1;
    }
    
    # array.
    if (ref $value eq 'ARRAY') {
        
        # add each item separately.
        my ($i, @ids) = 0;
        foreach my $item (@$value) {
        
            # determine the ID.
            push @ids, my $id = $valueid + ++$i;
        
            # insert the value.
            $edb->_db_store_value($id, undef, undef, undef, undef, $item);
        
        }
        
        # add the array itself.
        my $array_value = join ',', @ids;
        $insert->('array', $array_value, $value);

    }
    
    # array.
    if (ref $value eq 'HASH') {
        
        # add each item separately.
        my ($i, %ids) = 0;
        foreach my $_key (keys %$value) {
            my $item = $value->{$_key};
            
            # determine the ID.
            my $id = $valueid + ++$i;
            $ids{$_key} = $id;
        
            # insert the value
            $edb->_db_store_value($id, undef, undef, undef, undef, $item);
        
        }
        
        # add the hash itself.
        my $hash_value = join ',', map { $_.q(:).$ids{$_} } keys %ids;
        $insert->('hash', $hash_value, $value);

    }
    
}

#####################
### MISCELLANEOUS ###
#####################


# errors.
sub error {
    my ($edb, $reason) = @_;
    
    # if $reason is set, we're returning undefined and setting the error.
    if (defined $reason) {
        $edb->{EDB_ERROR} = $reason;
        return;
    }

    # otherwise, we're returning the last error set.
    return $edb->{EDB_ERROR};
    
}

# remove leading and trailing whitespace.
sub trim {
    my $string = shift;
    $string =~ s/\s+$//;
    $string =~ s/^\s+//;
    return $string;
}

1
