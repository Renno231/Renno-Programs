local path, ecc, mapToStr, lazyLoad, strToByteArr, byteTableMT = ...
if not (ecc and mapToStr and lazyLoad and strToByteArr and byteTableMT) then
    error((path or "modp.lua").." is a private sublibrary of ecc, use the ecc library instead")
end

-- Arithmetic on the finite field of integers modulo p = 481 * 2^159 + 3.
-- Elements are tables of seven 24-bit integer limbs, little-endian, always fully reduced.
-- Multiplication uses Montgomery form (r = 2^168) with word-by-word reduction: p has only
-- two non-zero limbs, so each reduction step costs two small multiplications.
-- Requires Lua 5.3+ integers and bitwise operators.
local modp = {}
local P7 = 15761408 -- top limb of p; the bottom limb is 3 and the rest are 0

-- Returns {t} reduced from [0, 2p) to [0, p).
local function reduce(t1, t2, t3, t4, t5, t6, t7)
    if t7 > P7 or (t7 == P7 and (t1 >= 3 or (t2 | t3 | t4 | t5 | t6) ~= 0)) then
        t1 = t1 - 3
        t7 = t7 - P7
        if t1 < 0 then
            t1 = t1 + 0x1000000; t2 = t2 - 1
            if t2 < 0 then
                t2 = t2 + 0x1000000; t3 = t3 - 1
                if t3 < 0 then
                    t3 = t3 + 0x1000000; t4 = t4 - 1
                    if t4 < 0 then
                        t4 = t4 + 0x1000000; t5 = t5 - 1
                        if t5 < 0 then
                            t5 = t5 + 0x1000000; t6 = t6 - 1
                            if t6 < 0 then t6 = t6 + 0x1000000; t7 = t7 - 1 end
                        end
                    end
                end
            end
        end
    end
    return {t1, t2, t3, t4, t5, t6, t7}
end

local function add(a, b)
    local c1, c2, c3, c4 = a[1] + b[1], a[2] + b[2], a[3] + b[3], a[4] + b[4]
    local c5, c6, c7 = a[5] + b[5], a[6] + b[6], a[7] + b[7]
    c2 = c2 + (c1 >> 24); c1 = c1 & 0xFFFFFF
    c3 = c3 + (c2 >> 24); c2 = c2 & 0xFFFFFF
    c4 = c4 + (c3 >> 24); c3 = c3 & 0xFFFFFF
    c5 = c5 + (c4 >> 24); c4 = c4 & 0xFFFFFF
    c6 = c6 + (c5 >> 24); c5 = c5 & 0xFFFFFF
    c7 = c7 + (c6 >> 24); c6 = c6 & 0xFFFFFF
    return reduce(c1, c2, c3, c4, c5, c6, c7)
end

local function sub(a, b)
    local c1, c2, c3, c4 = a[1] - b[1], a[2] - b[2], a[3] - b[3], a[4] - b[4]
    local c5, c6, c7 = a[5] - b[5], a[6] - b[6], a[7] - b[7]
    -- Borrow with arithmetic shifts: (x >> 24) is logical, so use floor division.
    c2 = c2 + c1 // 0x1000000; c1 = c1 & 0xFFFFFF
    c3 = c3 + c2 // 0x1000000; c2 = c2 & 0xFFFFFF
    c4 = c4 + c3 // 0x1000000; c3 = c3 & 0xFFFFFF
    c5 = c5 + c4 // 0x1000000; c4 = c4 & 0xFFFFFF
    c6 = c6 + c5 // 0x1000000; c5 = c5 & 0xFFFFFF
    c7 = c7 + c6 // 0x1000000; c6 = c6 & 0xFFFFFF
    if c7 < 0 then
        -- a - b + p
        c1 = c1 + 3; c7 = c7 + P7
        c2 = c2 + (c1 >> 24); c1 = c1 & 0xFFFFFF
        c3 = c3 + (c2 >> 24); c2 = c2 & 0xFFFFFF
        c4 = c4 + (c3 >> 24); c3 = c3 & 0xFFFFFF
        c5 = c5 + (c4 >> 24); c4 = c4 & 0xFFFFFF
        c6 = c6 + (c5 >> 24); c5 = c5 & 0xFFFFFF
        c7 = c7 + (c6 >> 24); c6 = c6 & 0xFFFFFF
    end
    return {c1, c2, c3, c4, c5, c6, c7}
end

local function mul(a, b)
    local a1, a2, a3, a4, a5, a6, a7 = a[1], a[2], a[3], a[4], a[5], a[6], a[7]
    local b1, b2, b3, b4, b5, b6, b7 = b[1], b[2], b[3], b[4], b[5], b[6], b[7]
    local c1 = a1*b1
    local c2 = a1*b2 + a2*b1
    local c3 = a1*b3 + a2*b2 + a3*b1
    local c4 = a1*b4 + a2*b3 + a3*b2 + a4*b1
    local c5 = a1*b5 + a2*b4 + a3*b3 + a4*b2 + a5*b1
    local c6 = a1*b6 + a2*b5 + a3*b4 + a4*b3 + a5*b2 + a6*b1
    local c7 = a1*b7 + a2*b6 + a3*b5 + a4*b4 + a5*b3 + a6*b2 + a7*b1
    local c8 = a2*b7 + a3*b6 + a4*b5 + a5*b4 + a6*b3 + a7*b2
    local c9 = a3*b7 + a4*b6 + a5*b5 + a6*b4 + a7*b3
    local c10 = a4*b7 + a5*b6 + a6*b5 + a7*b4
    local c11 = a5*b7 + a6*b6 + a7*b5
    local c12 = a6*b7 + a7*b6
    local c13 = a7*b7
    local c14 = 0
    local m
    m = (c1 * 0x555555) & 0xFFFFFF
    c2 = c2 + ((c1 + 3 * m) >> 24)
    c7 = c7 + 15761408 * m
    m = (c2 * 0x555555) & 0xFFFFFF
    c3 = c3 + ((c2 + 3 * m) >> 24)
    c8 = c8 + 15761408 * m
    m = (c3 * 0x555555) & 0xFFFFFF
    c4 = c4 + ((c3 + 3 * m) >> 24)
    c9 = c9 + 15761408 * m
    m = (c4 * 0x555555) & 0xFFFFFF
    c5 = c5 + ((c4 + 3 * m) >> 24)
    c10 = c10 + 15761408 * m
    m = (c5 * 0x555555) & 0xFFFFFF
    c6 = c6 + ((c5 + 3 * m) >> 24)
    c11 = c11 + 15761408 * m
    m = (c6 * 0x555555) & 0xFFFFFF
    c7 = c7 + ((c6 + 3 * m) >> 24)
    c12 = c12 + 15761408 * m
    m = (c7 * 0x555555) & 0xFFFFFF
    c8 = c8 + ((c7 + 3 * m) >> 24)
    c13 = c13 + 15761408 * m
    c9 = c9 + (c8 >> 24); c8 = c8 & 0xFFFFFF
    c10 = c10 + (c9 >> 24); c9 = c9 & 0xFFFFFF
    c11 = c11 + (c10 >> 24); c10 = c10 & 0xFFFFFF
    c12 = c12 + (c11 >> 24); c11 = c11 & 0xFFFFFF
    c13 = c13 + (c12 >> 24); c12 = c12 & 0xFFFFFF
    c14 = c14 + (c13 >> 24); c13 = c13 & 0xFFFFFF
    return reduce(c8, c9, c10, c11, c12, c13, c14)
end

local function sqr(a)
    local a1, a2, a3, a4, a5, a6, a7 = a[1], a[2], a[3], a[4], a[5], a[6], a[7]
    local c1 = a1*a1
    local c2 = a1*a2*2
    local c3 = a1*a3*2 + a2*a2
    local c4 = a1*a4*2 + a2*a3*2
    local c5 = a1*a5*2 + a2*a4*2 + a3*a3
    local c6 = a1*a6*2 + a2*a5*2 + a3*a4*2
    local c7 = a1*a7*2 + a2*a6*2 + a3*a5*2 + a4*a4
    local c8 = a2*a7*2 + a3*a6*2 + a4*a5*2
    local c9 = a3*a7*2 + a4*a6*2 + a5*a5
    local c10 = a4*a7*2 + a5*a6*2
    local c11 = a5*a7*2 + a6*a6
    local c12 = a6*a7*2
    local c13 = a7*a7
    local c14 = 0
    local m
    m = (c1 * 0x555555) & 0xFFFFFF
    c2 = c2 + ((c1 + 3 * m) >> 24)
    c7 = c7 + 15761408 * m
    m = (c2 * 0x555555) & 0xFFFFFF
    c3 = c3 + ((c2 + 3 * m) >> 24)
    c8 = c8 + 15761408 * m
    m = (c3 * 0x555555) & 0xFFFFFF
    c4 = c4 + ((c3 + 3 * m) >> 24)
    c9 = c9 + 15761408 * m
    m = (c4 * 0x555555) & 0xFFFFFF
    c5 = c5 + ((c4 + 3 * m) >> 24)
    c10 = c10 + 15761408 * m
    m = (c5 * 0x555555) & 0xFFFFFF
    c6 = c6 + ((c5 + 3 * m) >> 24)
    c11 = c11 + 15761408 * m
    m = (c6 * 0x555555) & 0xFFFFFF
    c7 = c7 + ((c6 + 3 * m) >> 24)
    c12 = c12 + 15761408 * m
    m = (c7 * 0x555555) & 0xFFFFFF
    c8 = c8 + ((c7 + 3 * m) >> 24)
    c13 = c13 + 15761408 * m
    c9 = c9 + (c8 >> 24); c8 = c8 & 0xFFFFFF
    c10 = c10 + (c9 >> 24); c9 = c9 & 0xFFFFFF
    c11 = c11 + (c10 >> 24); c10 = c10 & 0xFFFFFF
    c12 = c12 + (c11 >> 24); c11 = c11 & 0xFFFFFF
    c13 = c13 + (c12 >> 24); c12 = c12 & 0xFFFFFF
    c14 = c14 + (c13 >> 24); c13 = c13 & 0xFFFFFF
    return reduce(c8, c9, c10, c11, c12, c13, c14)
end


local R2 = {13533400, 837116, 6278376, 13533388, 837116, 6278376, 7504076} -- r^2 mod p

-- Integer limbs, whatever number subtype the caller produced.
local function ints(a)
    return {a[1] | 0, a[2] | 0, a[3] | 0, a[4] | 0, a[5] | 0, a[6] | 0, a[7] | 0}
end

local function montgomeryModP(a)
    return mul(ints(a), R2)
end

local function inverseMontgomeryModP(a)
    return mul(a, {1, 0, 0, 0, 0, 0, 0})
end

local ONE = montgomeryModP({1, 0, 0, 0, 0, 0, 0})

-- exponentBinary: 168 bits, least significant first
local function expModP(base, exponentBinary)
    local result = ONE
    for i = 1, 168 do
        if exponentBinary[i] == 1 then
            result = mul(result, base)
        end
        base = sqr(base)
    end
    return result
end

modp.addModP = add
modp.subModP = sub
modp.multModP = mul
modp.squareModP = sqr
modp.montgomeryModP = montgomeryModP
modp.inverseMontgomeryModP = inverseMontgomeryModP
modp.expModP = expModP
modp.ints = ints
return modp
