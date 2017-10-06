# lua_bnstring

Integer bignums for lua

Augment strings so that they can be used as integer bignums with
standard arithmetic operations.

(Requires lua 5.3 or greater.)

This module extends normal lua string-to-number conversion.

Any string will be considered a number if it satisfies the following:

    remove all non-numeric characters except minus signs and periods.
    expect at most one minus sign, at the beginning.
    expect at least one numeric character.
    expect at most one period, followed by zero or more '0' characters.

String results are comma-separated if they have enough significant digits,
or suffixed with 'd' (for decimal).

If lua can interpret all operands of an arithmetic operation as numbers,
then it will do the arithmetic itself.  If at least one operand is not
recognizable to lua as a number, then the operations implemented herein
will be used.

Unfortunately, the lua comparison operators do not fall back on string
metatable operations in ways that would be compatible with strings
interpreted as big integers.  So, comparison operators (and a couple of other
useful bignum arithmetic operators) must be invoked using the lua object
notation.

Usage:

    > require 'bnstring'
    
    > '10d' + '10d'
    20d
    
    > '1,000' + '10'
    '1,010'
    
    > '10d' ^ '10'
    10,000,000,000
    
    > 10 ^ 50
    1e+50
    
    > '10' ^ 50
    1e+50
    
    > '10d' ^ 50
    100,000,000,000,000,000,000,000,000,000,000,000,000,000,000,000,000
    
    > ('4d'):lt(10)
    true

Operations:
* a + b
* a - b
* -a
* a * b
* a ^ b
* a // b
* a % b
* a:lt(b)
* a:le(b)
* a:eq(b)
* a:ge(b)
* a:gt(b)
* a:powmod(b)
