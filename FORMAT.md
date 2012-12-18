# EVENTED::DATABASE FORMAT

This file describes the Evented::Database storage format.

# Data types

There are 4 basic data types:

* __string:__ a string.
* __number:__ a float or integer.
* __array:__ an ordered list of other data types.
* __hash:__ a key:value dictionary.

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
--------------------
| VALUEID  | VALUE |
--------------------
| value_id | value |
--------------------

```

### Data stored in this table

* __value_id__: the identifier of the value in the value table.
* __value_type__: the string type of the value as seen in "Data types" above.

