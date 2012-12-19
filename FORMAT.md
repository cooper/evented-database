# EVENTED::DATABASE FORMAT

This file describes the Evented::Database storage format.

# Data types

There are 4 basic data types:

* __string__: a string.
* __number__:  a float or integer.
* __array__: an ordered list of other data types.
* __hash__: a key:value dictionary.

## Storage syntax

All data is stored as strings; they must be encoded and parsed into the below formats.

### Numbers

Numbers are nothing more than numbers. No need to make it complicated.

```
1
46
3.5
0.5553
```

### Strings

Strings are stored wrapped in double quotes. Any double quotes in itself should be
escaped with the backslash character. Backslashes can be escaped as well.

```
"some simple string"
"a string with \"quotes\" in it"
"a string with a backslash (\\) in it"
```

### Arrays

List values are comma-separated value identifiers.

```
4,5,6,7
1,2,3,4,5,6
```

### Hashes

Hash pairs are comma-separated, in the form of key:value_identifier.

```perl
myKey:34,otherKey:37,someOtherkey:983
```

# Tables

Evented::Database uses two databases: one for storing the location of values and one for
the values themselves.

## The location table

The location table (LOCATIONS) stores the locations of values by using numerical
identifiers. Each value has a unique identifier. 

```
--------------------------------------------
| BLOCK      | BLOCKNAME  | KEY | VALUEID  |
--------------------------------------------
| block_type | block_name | key | value_id |
--------------------------------------------
```

### Data stored in this table

* __block_type__: the string type of the block for named blocks; "section" for unnamed.
* __block_name__: the string name of the block.
* __key__: the string key this value represents.
* __value_id__: the identifier of the value in the value table.

## The value table

The value table (VALUES) stores the actual values and their identifiers. It also stores
the type of the value.

```
---------------------------------
| VALUEID  | VALUETYPE  | VALUE |
---------------------------------
| value_id | value_type | value |
---------------------------------
```

### Data stored in this table

* __value_id__: the identifier of the value in the value table.
* __value_type__: the string type of the value as seen in "Data types" above.
* __value__: the value being stored in the syntax seen in "Storage syntax" above.

