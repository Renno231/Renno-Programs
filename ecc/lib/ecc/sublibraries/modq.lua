local path, ecc, mapToStr, lazyLoad, strToByteArr, byteTableMT = ...
if not (ecc and mapToStr and lazyLoad and strToByteArr and byteTableMT) then
    error((path or "modq.lua").." is a private sublibrary of ecc, use the ecc library instead")
end
local unpack = table.unpack

-- Arithmetic on the Finite Field of Integers modulo q
-- Where q is the generator's subgroup order.
local modq = {}
local random = lazyLoad("random")
local sha256 = lazyLoad("sha256")
local isEqual = lazyLoad("arith","isEqual")
local compare = lazyLoad("arith", "compare")
local add = lazyLoad("arith", "add")
local sub = lazyLoad("arith", "sub")
local addDouble = lazyLoad("arith", "addDouble")
local mult = lazyLoad("arith", "mult")
local square = lazyLoad("arith", "square")
local encodeInt = lazyLoad("arith", "encodeInt")
local decodeInt = lazyLoad("arith", "decodeInt")

local modQMT

local q = {9622359, 6699217, 13940450, 16775734, 16777215, 16777215, 3940351}
local qMinusTwoBinary = {1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1}

-- We're using the Montgomery Reduction for fast modular multiplication.
-- https://en.wikipedia.org/wiki/Montgomery_modular_multiplication 
-- r = 2^168
-- q * qInverse = -1 (mod r)
-- r2 = r * r (mod q)
local qInverse = {15218585, 5740955, 3271338, 9903997, 9067368, 7173545, 6988392}
local r2 = {1336213, 11071705, 9716828, 11083885, 9188643, 1494868, 3306114}

-- Reduces a number from [0, 2q - 1] to [0, q - 1]
local function reduceModQ(a)
    local result = {unpack(a)}

    if compare(result, q) >= 0 then
        result = sub(result, q)
    end

    return setmetatable(result, modQMT)
end

local function addModQ(a, b)
    return reduceModQ(add(a, b))
end

local function subModQ(a, b)
    local result = sub(a, b)

    if result[7] < 0 then
        result = add(result, q)
    end

    return setmetatable(result, modQMT)
end

-- Montgomery REDC algorithn
-- Reduces a number from [0, q^2 - 1] to [0, q - 1]
local function REDC(T)
    local m = {unpack(mult({unpack(T, 1, 7)}, qInverse, true), 1, 7)}
    local t = {unpack(addDouble(T, mult(m, q)), 8, 14)}

    return reduceModQ(t)
end

local function multModQ(a, b)
    -- Only works with a, b in Montgomery form
    return REDC(mult(a, b))
end

local function squareModQ(a)
    -- Only works with a in Montgomery form
    return REDC(square(a))
end

local function montgomeryModQ(a)
    return multModQ(a, r2)
end

local function inverseMontgomeryModQ(a)
    local a = {unpack(a)}

    for i = 8, 14 do
        a[i] = 0
    end

    return REDC(a)
end

local ONE = montgomeryModQ({1, 0, 0, 0, 0, 0, 0})

local function expModQ(base, exponentBinary)
    local base = {unpack(base)}
    local result = {unpack(ONE)}

    for i = 1, 168 do
        if exponentBinary[i] == 1 then
            result = multModQ(result, base)
        end
        base = squareModQ(base)
    end

    return result
end

local function intExpModQ(base, exponent)
    local base = {unpack(base)}
    local result = setmetatable({unpack(ONE)}, modQMT)

    if exponent < 0 then
        base = expModQ(base, qMinusTwoBinary)
        exponent = -exponent
    end

    while exponent > 0 do
        if exponent % 2 == 1 then
            result = multModQ(result, base)
        end
        base = squareModQ(base)
        exponent = exponent / 2
        exponent = exponent - exponent % 1
    end 

    return result
end

local function encodeModQ(a)
    local result = encodeInt(a)

    return setmetatable(result, byteTableMT)
end

local function decodeModQ(s)
    local result = decodeInt(strToByteArr(mapToStr(s):sub(1, 21)))
    result[7] = result[7] % q[7]

    return setmetatable(result, modQMT)
end

local function randomModQ()
    while true do
        local s = {unpack(random.random(), 1, 21)}
        local result = decodeInt(s)
        if result[7] < q[7] then
            return setmetatable(result, modQMT)
        end
    end
end

local function hashModQ(data)
    return decodeModQ(sha256.digest(data))
end

modQMT = {
    __index = {
        encode = function(self)
            return encodeModQ(self)
        end
    },

    __tostring = function(self)
        return self:encode():toHex()
    end,

    __add = function(self, other)
        if type(self) == "number" then
            return other + self
        end

        if type(other) == "number" then
            assert(other < 2^24, "number operand too big")
            other = montgomeryModQ({other, 0, 0, 0, 0, 0, 0})
        end

        return addModQ(self, other)
    end,

    __sub = function(a, b)
        if type(a) == "number" then
            assert(a < 2^24, "number operand too big")
            a = montgomeryModQ({a, 0, 0, 0, 0, 0, 0})
        end

        if type(b) == "number" then
            assert(b < 2^24, "number operand too big")
            b = montgomeryModQ({b, 0, 0, 0, 0, 0, 0})
        end

        return subModQ(a, b)
    end,

    __unm = function(self)
        return subModQ(q, self)
    end,

    __eq = function(self, other)
        return isEqual(self, other)
    end,

    __mul = function(self, other)
        if type(self) == "number" then
            return other * self
        end

        -- EC point
        -- Use the point's metatable to handle multiplication
        if type(other) == "table" and type(other[1]) == "table" then
            return other * self
        end

        if type(other) == "number" then
            assert(other < 2^24, "number operand too big")
            other = montgomeryModQ({other, 0, 0, 0, 0, 0, 0})
        end

        return multModQ(self, other)
    end,

    __div = function(a, b)
        if type(a) == "number" then
            assert(a < 2^24, "number operand too big")
            a = montgomeryModQ({a, 0, 0, 0, 0, 0, 0})
        end

        if type(b) == "number" then
            assert(b < 2^24, "number operand too big")
            b = montgomeryModQ({b, 0, 0, 0, 0, 0, 0})
        end

        local bInv = expModQ(b, qMinusTwoBinary)

        return multModQ(a, bInv)
    end,

    __pow = function(self, other)
        return intExpModQ(self, other)
    end
}


modq.hashModQ = hashModQ
modq.randomModQ = randomModQ
modq.decodeModQ = decodeModQ
modq.inverseMontgomeryModQ = inverseMontgomeryModQ
return modq