-----------------------------------------------------------------------------
-- Copyright (c) Greg Johnson, Gnu Public Licence v. 2.0.
-----------------------------------------------------------------------------
--[[
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
    a + b
    a - b
    -a
    a * b
    a ^ b
    a // b
    a % b
    a:lt(b)
    a:le(b)
    a:eq(b)
    a:ge(b)
    a:gt(b)
    a:powmod(b)
--]]

local version = '0.1.0'

local zero = ('0'):byte()
local abs
local add
local pow
local powmod
local cleanup
local digitToString
local fixForSign
local divide
local divideSingleDigit
local initialCleanup
local finalCleanup
local isEven
local isNeg
local isZero
local mult
local multSingleDigit
local negate
local normalize
local nthPower
local subtract

local lt
local le
local eq
local ge
local gt

local verbose = false

function nthPower(number, index, endindex)
    endindex = endindex or index
    if index == endindex then
        index = #number - index
        return (1 <= index and index <= #number) and (number:byte(index) - zero) or 0
    end

    local result = 0
    for i = endindex, index, -1 do
        result = result * 10 + nthPower(number, i)
    end

    return result
end
if TESTX then
    test:check(0, nthPower('1234567890', 100), 'nthPower')
    test:check(2, nthPower('23456', 4, 4), 'nthPower')
    test:check(23, nthPower('23456', 3, 4), 'nthPower')
    test:check(1234567, nthPower('1234567890', 3, 9), 'nthPower')
    test:check(0, nthPower('1234567890', 13, 19), 'nthPower')
end

function isEven(n)
    local lastDigit = nthPower(n, 0)
    return (lastDigit % 2) == 0
end

function digitToString(s)
    return string.char(s + zero)
end

function abs(s1)
    return s1:gsub('^-', '')
end
if TESTX then
    test:check('5', abs('-5'), 'abs')
    test:check('5', abs('5'), 'abs')
end

function isNeg(s1)
    return s1:sub(1,1) == '-' and s1:match('[1-9]') ~= nil
end
if TESTX then
    test:check(true, isNeg('-5'), 'isNeg(-5)')
    test:check(false, isNeg('5'), 'isNeg(5)')
    test:check(false, isNeg('0'), 'isNeg(0)')
    test:check(false, isNeg('-0'), 'isNeg(-0)')
    test:check(true, isNeg('-011'), 'isNeg(-011)')
end

function negate(s)
    if isNeg(s) then return abs(s) end
    if isZero(s) then return(s) end
    return '-' .. s
end

function cleanup(str)
    if type(str) ~= 'string' then str = tostring(str) end
    if isNeg(str) then
        return '-' .. cleanup(abs(str))
    end
    str = str:gsub('^0+', ''):gsub('^-', '')
    if #str == 0 then str = '0' end
    return str
end
if TESTX then
    test:check('0', cleanup('-0'), 'cleanup(-0)')
end

-- remove all non-numeric characters except minus sign.
-- expect at most one minus sign, at beginning.
-- expect at least one numeric character.
--
function initialCleanup(str)
    if type(str) == 'number' then
        assert(str % 1 == 0, 'number has no integer representation')
        str = tostring(str)
        str = str:gsub('%..*', '')

    elseif type(str) ~= 'string' then
        str = tostring(str)
    end

    local result = str:gsub('[^%.-0-9]', '')
    assert(result:sub(2):match('-') == nil, "string does not contain a number")
    assert(result:match('%..*%.') == nil, "string does not contain a number")
    assert(result:match('%..*[1-9]') == nil, "string does not contain an integer")
    assert(result:match('%d'), "string does not contain a number")
    result = cleanup(result)
    return result
end
if TEST then
    test:check('123', initialCleanup('123s'), 'initialCleanup(123s)')
    test:check('-123', initialCleanup('-123s'), 'initialCleanup(-123s)')
    test:check('-123', initialCleanup('   -123s'), 'initialCleanup(   -123s)')
    test:check(false, pcall(function() initialCleanup('--4') end))
    test:check(false, pcall(function() initialCleanup('abc') end))
    test:check(false, pcall(function() initialCleanup('3.14') end))
    test:check(false, pcall(function() initialCleanup('3.14.15') end))
    test:check(true,  pcall(function() initialCleanup('3.000') end))
    test:check(true,  pcall(function() initialCleanup('-3.000') end))
    test:check(true,  pcall(function() initialCleanup('3.') end))
    test:check(true,  pcall(function() initialCleanup('-3.') end))
end

-- assume str matches "^%-?[0-9]+$".
-- return nn,nnn,nnn if at least 3 digits, or nns
--
function finalCleanup(str)
    local result

    local neg = isNeg(str)
    if neg then str = abs(str) end

    if #str < 4 then
        result = str .. 'd'
    else
        result = ''
        for posn = #str, 1, -3 do
            local start = posn - 2
            if start < 1 then start = 1 end
            result = str:sub(start, posn) .. result
            if start > 1 then result = ',' .. result end
        end
    end

    if neg then result = '-' .. result end

    return result
end

if TESTX then
    test:check('123,456,789', finalCleanup('123456789'), "finalCleanup('123456789')")
    test:check('23,456,789', finalCleanup('23456789'), "finalCleanup('23456789')")
    test:check('23,456,789', finalCleanup('23456789'), "finalCleanup('23456789')")
    test:check('3,456,789', finalCleanup('3456789'), "finalCleanup('3456789')")
    test:check('456,789', finalCleanup('456789'), "finalCleanup('456789')")
    test:check('56,789', finalCleanup('56789'), "finalCleanup('56789')")
    test:check('6,789', finalCleanup('6789'), "finalCleanup('6789')")
    test:check('789s', finalCleanup('789'), "finalCleanup('789')")
    test:check('89s', finalCleanup('89'), "finalCleanup('89')")
    test:check('9s', finalCleanup('9'), "finalCleanup('9')")
    test:check('0s', finalCleanup('0'), "finalCleanup('0')")
    test:check('-12s', finalCleanup('-12'), "finalCleanup('-12')")
    test:check('-123s', finalCleanup('-123'), "finalCleanup('-123')")
    test:check('-1,234', finalCleanup('-1234'), "finalCleanup('-1,234')")
end

function isZero(s)
    return cleanup(s) == '0'
end

function lt(s1, s2)
    if isNeg(s1) and not isNeg(s2) then return true end
    if isNeg(s2) and not isNeg(s1) then return false end
    if isNeg(s1) and isNeg(s2) then return lt(abs(s2), abs(s1)) end
    s1 = cleanup(s1)
    s2 = cleanup(s2)
    if #s1 < #s2 then return true end
    if #s1 > #s2 then return false end
    for i = 1, #s1 do
        if s1:byte(i) < s2:byte(i) then return true end
        if s1:byte(i) > s2:byte(i) then return false end
    end
    return false
end
if TESTX then
    test:check(true, lt('-0', '5'), 'lt(-0, 5)')
    test:check(true, lt('5', '6'), 'lt(5, 6)')
    test:check(false, lt('5', '5'), 'lt(5, 5)')
    test:check(false, lt('5', '4'), 'lt(5, 4)')

    test:check(false, lt('-5', '-6'), 'lt(-5, -6)')
    test:check(false, lt('-5', '-5'), 'lt(-5, -5)')
    test:check(true, lt('-5', '4'), 'lt(-5, -4)')

    test:check(true, lt('-5', '5'), 'lt(-5, 5)')
    test:check(false, lt('5', '-5'), 'lt(5, -5)')

    test:check(true, lt('5', '50'), 'lt(5, 50)')
    test:check(false, lt('50', '5'), 'lt(50, 5)')
    test:check(true, lt('0', '5'), 'lt(0, 5)')

    test:check(true, lt('1111111', '1111112'), 'lt(1111111, 1111112)')
end

function le(s1, s2)
    return lt(s1, s2) or eq(s1, s2)
end

function eq(s1, s2)
    return not lt(s1, s2) and not lt(s2, s1)
end

function ge(s1, s2)
    return le(s2, s1)
end

function gt(s1, s2)
    return lt(s2, s1)
end

function add(s1, s2)
    if not isNeg(s1) and     isNeg(s2) then return subtract(s1, abs(s2))         end
    if     isNeg(s1) and not isNeg(s2) then return subtract(s2, abs(s1))         end
    if     isNeg(s1) and     isNeg(s2) then return negate(add(abs(s1), abs(s2))) end

    local result = ''
    local s1index = 0
    local s2index = 0
    local carry = 0

    while s1index < #s1 or s2index < #s2 do
        local digit1 = nthPower(s1, s1index)
        local digit2 = nthPower(s2, s2index)

        local value = carry + digit1 + digit2

        local digit = value % 10
        carry = value // 10

        result = digitToString(digit) .. result

        s1index = s1index + 1
        s2index = s2index + 1
    end

    if carry ~= 0 then
        result = digitToString(carry) .. result
    end

    return cleanup(result)
end
if TESTX then
    test:check('4', add('2', '2'), '2+2')
    test:check('18', add('9', '9'), '9+9')
    test:check('100', add('99', '1'), '99+1')
    test:check('-4', add('-2', '-2'), '-2+-2')
end

function subtract(s1, s2)
    if lt(s1, s2)                  then return negate(subtract(s2, s1))           end 

    if     isNeg(s1) and isNeg(s2) then return negate(subtract(abs(s1), abs(s2))) end
    if not isNeg(s1) and isNeg(s2) then return add(s1, abs(s2))                   end

    local result = ''
    local s1index = 0
    local s2index = 0
    local borrow = 0

    while s1index < #s1 or s2index < #s2 do
        local digit1 = nthPower(s1, s1index)
        local digit2 = nthPower(s2, s2index)

        local value = digit1 - digit2 + borrow

        local digit = value % 10
        borrow = value // 10

        result = digitToString(digit) .. result

        s1index = s1index + 1
        s2index = s2index + 1
    end

    return cleanup(result)
end
if TESTX then
    test:check('1', subtract('2', '1'), '2-1')
    test:check('-1', subtract('1', '2'), '1-2')
    test:check('0', subtract('9', '9'), '9-9')
    test:check('98', subtract('99', '1'), '99-1')
    test:check('89', subtract('90', '1'), '90-1')
    test:check('999999', subtract('1000000', '1'), '1000000-1')

    test:check('-1', subtract('-2', '-1'), '-2 - -1')
    test:check('-2', subtract('-4', '-2'), '-4 - -2')
    test:check('-6', subtract('-4', '2'), '-4 - 2')
end

function multSingleDigit(s, singleDigit)
    local result = ''
    local carry = 0

    for i = 0, #s-1 do
        local value = carry + nthPower(s, i) * singleDigit

        local digit = value % 10
        carry = value // 10

        result = digitToString(digit) .. result
    end

    if carry ~= 0 then
        result = digitToString(carry) .. result
    end

    return result
end
if TESTX then
    test:check('4', multSingleDigit('2', 2), '2*2')
    test:check('24', multSingleDigit('6', 4), '6*4')
    test:check('81', multSingleDigit('9', 9), '9*9')
    test:check('89991', multSingleDigit('9999', 9), '9999*9')
    test:check('60', multSingleDigit('12', 5), '12*5')
end

function mult(s1, s2)
    local neg = isNeg(s1) ~= isNeg(s2)
    s1 = abs(s1)
    s2 = abs(s2)

    local result = '0'
    local zeroes = ''

    for i = #s2-1, 0, -1 do
        local p1 = multSingleDigit(s1, nthPower(s2, i))
        result = add(result..'0', p1)
    end

    if neg then result = negate(result) end

    return result
end
if TESTX then
    test:check('4', mult('2', '2'), '2*2')
    test:check('24', mult('6', '4'), '6*4')
    test:check('81', mult('9', '9'), '9*9')
    test:check('89991', mult('9999', '9'), '9999*9')
    test:check('60', mult('12', '5'), '12*5')
    test:check('144', mult('12', '12'), '12*12')
    test:check('-144', mult('-12', '12'), '-12*12')
end

function normalize(num, den)
    local leadingDigit = nthPower(den, 1)
    local mult

    if leadingDigit >= 5 then
        return num, den, 1

    elseif leadingDigit == 1 then
        mult = 5

    elseif leadingDigit == 2 then
        mult = 3

    else -- 3 or 4
        mult = 2
    end

    return multSingleDigit(num, mult), multSingleDigit(den, mult), mult

end
if TESTX then
    local n,d,m = normalize('111', '55')
    test:check('111', n, '111, 55 num')
    test:check('55',  d, '111, 55 den')
    test:check(1,     m, '111, 55 mult')

    n,d,m = normalize('111', '44')
    test:check('222', n, '111, 44 num')
    test:check('88',  d, '111, 44 den')
    test:check(2,     m, '111, 44 mult')

    n,d,m = normalize('111', '33')
    test:check('222', n, '111, 33 num')
    test:check('66',  d, '111, 33 den')
    test:check(2,     m, '111, 33 mult')

    n,d,m = normalize('111', '22')
    test:check('333', n, '111, 22 num')
    test:check('66',  d, '111, 22 den')
    test:check(3,     m, '111, 22 mult')

    n,d,m = normalize('111', '11')
    test:check('555', n, '111, 11 num')
    test:check('55',  d, '111, 11 den')
    test:check(5,     m, '111, 11 mult')
end

function fixForSign(quot, rem, den, negNum, negDen)
    if verbose then print('fixForSign', quot, rem, den, negNum, negDen) end

    if negNum and negDen then
        if verbose then print('nn') end
        rem = negate(rem)
        if verbose then print('fixForSign n n', quot, rem) end
    end

    if not negNum and negDen then
        if verbose then print('pn') end
        quot = negate(quot)
        if not isZero(rem) then
            quot = subtract(quot, '1')
            rem = subtract(rem, den)
        end
    end

    if negNum and not negDen then
        if verbose then print('np') end
        quot = negate(quot)
        if not isZero(rem) then
            quot = subtract(quot,'1')
            rem = subtract(den, rem)
        end
    end

    return quot, rem
end

function divideSingleDigit(num, den)
    local result = ''
    local rem = 0

    for i = #num-1,0, -1 do
        local n = 10 * rem + nthPower(num, i)
        result = result .. digitToString(n // den)
        rem = n % den
    end

    if #result == 0 then result = '0' end

    return cleanup(result), digitToString(rem)
end
if TESTX then
    test:check('3', divideSingleDigit('9', 3), '9/3')
    test:check('3', divideSingleDigit('10', 3), '10/3')
    test:check('24', divideSingleDigit('144', 6), '144/6')
    local q,r = divideSingleDigit('100', 3)
    test:check('1', r, '100 % 3')
end

function divide(num, den)
    num = initialCleanup(num)
    den = initialCleanup(den)

    local negativeNum = isNeg(num)
    local negativeDen = isNeg(den)
    num = abs(num)
    den = abs(den)

    local quot = '0'
    local norm

    if verbose then print('single digit den?', den, type(den)) end

    if #den == 1 then
        if verbose then
            print('yes')
            print('dsd', divideSingleDigit(num, nthPower(den, 0)))
        end
        local q, r = divideSingleDigit(num, nthPower(den, 0))

        if verbose then print(q,type(q),r,type(r)) end

        return fixForSign(q, r, den, negativeNum, negativeDen)
    end
    if verbose then print('no') end

    num, den, norm = normalize(num, den)
    if verbose then printf('norm %s %s %d\n', num, den, norm) end

    local den1, den2 = nthPower(den, #den-1), nthPower(den, #den-2)

    local numtail = num:sub(#den+1)
    num = num:sub(1, #den)

    while true do
        local numprefix, num3

        --printf("start loop num %s, numtail %s, quot %s\n", num, numtail, quot)

        numprefix, num3 = nthPower(num, #den-1, #den), nthPower(num, #den-2)

        local q = numprefix // den1
        local r = numprefix %  den1

        --printf("num %s, numtail %s, numprefix %d, den1 %d, q %d, r %d\n", 
        --        num,    numtail,    numprefix,    den1,    q,    r)

        while (q >= 10) or ((r < 10) and (q * den2) > (r*10 + num3)) do
            --printf('loop %d %d\n', q, r)
            q = q - 1
            r = r + den1
        end
        --printf('after loop %d %d\n', q, r)

        if q > 0 then
            --printf("num %s - den1 %s * q %d\n", num, den, q)
            num = subtract(num, multSingleDigit(den, q))
            --printf("sub num %s\n", num)

            while isNeg(num) do
                num = add(num, den)
                q = q - 1
                --printf("add loop num %s, q %d\n", num, q)
            end
        end

        quot = quot .. digitToString(q)
        --printf('quot %s, q %d, num %s\n\n', quot, q, num)

        if #numtail == 0 then break end

        num = num .. numtail:sub(1,1)
        numtail = numtail:sub(2)
    end

    rem = divideSingleDigit(num, norm)

    return fixForSign(cleanup(quot), rem, den, negativeNum, negativeDen)
end
if TESTX then
     test:check('3', divide('9', '3'), '9/3') -- ok
     test:check('1', divide('50', '50'), '50/50') -- ok
     test:check('3', divide('150', '50'), '150/50') -- ok
     test:check('8', divide('400', '50'), '400/50') -- ok
     test:check('8', divide('500', '59'), '500/59') -- ok
     test:check(tostring(65536/64 | 0), divide('65536', '64'), '65536/64') -- ok
     local q,r
     q,r = divide(' 10s', ' 8s') test:check( '1', q, '10/8');   test:check( '2', r, '10%8')
     q,r = divide(' 10s', '-8s') test:check('-2', q, '10/-8');  test:check('-6', r, '10%-8')
     q,r = divide('-10s', ' 8s') test:check('-2', q, '-10/8');  test:check( '6', r, '-10%8')
     q,r = divide('-10s', '-8s') test:check( '1', q, '-10/-8'); test:check('-2', r, '-10%-8')

     -- positive divisor; sane modular arithmetic.
     test:check('-2', divide('-10s',  '9s'), '-10 //  9')

     -- negative divisor; remainder has same sign
     -- as divisor.
     test:check('-2',  divide('10s', '-9s'), ' 10 // -9')

     test:check( '1', divide('-10s', '-9s'), '-10 // -9')
end

function pow(x, n)
    assert(not isNeg(n), 'negative exponent')
    local a = '1'

    -- result = a * x^n
    while not isZero(n) do
        if isEven(n) then
            -- x = (x^2)^(n/2)
            x = mult(x, x)
            n = divide(n, '2')
        else
            -- result = a * x * x^(n-1)
            a = mult(a, x)
            n = subtract(n, '1')
        end
    end

    return a
end
if TESTX then
    test:check('4', pow('2', '2'), '2^2')
    test:check('8', pow('2', '3'), '2^3')
    test:check('100000', pow('10', '5'), '10^5')
end

function powmod(x, n, m)
    local _
    assert(not isNeg(n), 'negative exponent')
    local a = '1'

    -- result = a * x^n
    while not isZero(n) do
        if isEven(n) then
            -- x = (x^2)^(n/2)
            _, x = divide(mult(x, x), m)
            n = divide(n, '2')
        else
            -- result = a * x * x^(n-1)
            _, a = divide(mult(a, x), m)
            n = subtract(n, '1')
        end
    end

    return a
end
if TESTX then
    test:check('1', powmod('2', '2', '3'), '2^2 mod 3')
    test:check('2', powmod('2', '3', '3'), '2^3 mod 3')
    test:check('1', powmod('10', '5', '3'), '10^5 mod 3')
end

local string_mt = getmetatable('a')

string_mt.__add  =  function(a, b) return finalCleanup(add(initialCleanup(a), initialCleanup(b))) end
string_mt.__sub  =  function(a, b) return finalCleanup(subtract(initialCleanup(a), initialCleanup(b))) end
string_mt.__unm  =  function(a)    return finalCleanup(negate(initialCleanup(a))) end
string_mt.__mul  =  function(a, b) return finalCleanup(mult(initialCleanup(a), initialCleanup(b))) end
string_mt.__pow  =  function(a, b) return finalCleanup(pow(initialCleanup(a), initialCleanup(b))) end
string_mt.__mod  =  function(a, b) local _, result = divide(initialCleanup(a), initialCleanup(b)); return finalCleanup(result) end
string_mt.__idiv = function(a, b) return finalCleanup(divide(initialCleanup(a), initialCleanup(b))) end
string_mt.__index.lt = function(a, b) return lt(initialCleanup(a), initialCleanup(b)) end
string_mt.__index.le = function(a, b) return le(initialCleanup(a), initialCleanup(b)) end
string_mt.__index.eq = function(a, b) return eq(initialCleanup(a), initialCleanup(b)) end
string_mt.__index.ge = function(a, b) return ge(initialCleanup(a), initialCleanup(b)) end
string_mt.__index.gt = function(a, b) return gt(initialCleanup(a), initialCleanup(b)) end
string_mt.__index.powmod = function(a, b, c) return finalCleanup(powmod(initialCleanup(a), initialCleanup(b), initialCleanup(c))) end

if TESTX then
    test:check('1s',      '-3s' + '4s', 'add metatable')
    test:check('-7s',     '-3s' - '4s', 'subtract metatable')
    test:check('7s',    - '-7s', 'subtract metatable')
    test:check('77s',     '11s' * '7s', 'multiply metatable')
    test:check('5s',      '10s' // '2s', 'divide metatable')
    test:check('3s',      '13s' % '5s', 'mod metatable')
    test:check('100,000', '10s' ^ '5s', '10^5')
    test:check(true, ('10s'):lt('50s'), 'lt')
    test:check('1s', ('10s'):powmod('5s', '3s'), 'powmod')
    test:check(true, ('10s'):lt('15s'), 'lt')
end
