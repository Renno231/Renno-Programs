local path, ecc, mapToStr, lazyLoad, strToByteArr, byteTableMT = ...
if not (ecc and mapToStr and lazyLoad and strToByteArr and byteTableMT) then
    error((path or "sha256.lua").." is a private sublibrary of ecc, use the ecc library instead")
end

-- SHA-256, HMAC and PBKDF2 on Lua 5.3 integers.
-- Same interface and outputs as the ComputerCraft version by Anavrins
-- (http://pastebin.com/6UV4qfNF) that this replaces.
local sha256 = {}
local spack, sunpack, srep = string.pack, string.unpack, string.rep
local concat, unpack = table.concat, table.unpack
local clock, sleep = os.clock, os.sleep

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local H0 = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19}
local M = 0xffffffff

local BLOCK = ">I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4"
local WORDS8 = ">I4I4I4I4I4I4I4I4"

-- One compression: the eight state words and the sixteen message words in, the new state out.
-- Sixteen rounds are written out per loop pass so the message words stay in locals (the
-- schedule overwrites them in place); instead of shifting the state each round the variable
-- names rotate, and they are back in place after every eight rounds.
-- Rotations use x | x << 32: a right shift of that has the 32-bit rotation in its low bits.
-- Bits above 32 only carry upward in sums, so values are masked once when they are stored.
local function block(a, b, c, d, e, f, g, h, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15, w16)
    local a0, b0, c0, d0, e0, f0, g0, h0 = a, b, c, d, e, f, g, h
    local t, u
    for j = 1, 64, 16 do
        t = e | e << 32; t = h + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (g ~ (e & (f ~ g))) + K[j] + w1
        d = (d + t) & M; u = a | a << 32
        h = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((a & b) | (c & (a | b)))) & M
        t = d | d << 32; t = g + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (f ~ (d & (e ~ f))) + K[j + 1] + w2
        c = (c + t) & M; u = h | h << 32
        g = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((h & a) | (b & (h | a)))) & M
        t = c | c << 32; t = f + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (e ~ (c & (d ~ e))) + K[j + 2] + w3
        b = (b + t) & M; u = g | g << 32
        f = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((g & h) | (a & (g | h)))) & M
        t = b | b << 32; t = e + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (d ~ (b & (c ~ d))) + K[j + 3] + w4
        a = (a + t) & M; u = f | f << 32
        e = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((f & g) | (h & (f | g)))) & M
        t = a | a << 32; t = d + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (c ~ (a & (b ~ c))) + K[j + 4] + w5
        h = (h + t) & M; u = e | e << 32
        d = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((e & f) | (g & (e | f)))) & M
        t = h | h << 32; t = c + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (b ~ (h & (a ~ b))) + K[j + 5] + w6
        g = (g + t) & M; u = d | d << 32
        c = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((d & e) | (f & (d | e)))) & M
        t = g | g << 32; t = b + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (a ~ (g & (h ~ a))) + K[j + 6] + w7
        f = (f + t) & M; u = c | c << 32
        b = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((c & d) | (e & (c | d)))) & M
        t = f | f << 32; t = a + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (h ~ (f & (g ~ h))) + K[j + 7] + w8
        e = (e + t) & M; u = b | b << 32
        a = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((b & c) | (d & (b | c)))) & M
        t = e | e << 32; t = h + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (g ~ (e & (f ~ g))) + K[j + 8] + w9
        d = (d + t) & M; u = a | a << 32
        h = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((a & b) | (c & (a | b)))) & M
        t = d | d << 32; t = g + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (f ~ (d & (e ~ f))) + K[j + 9] + w10
        c = (c + t) & M; u = h | h << 32
        g = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((h & a) | (b & (h | a)))) & M
        t = c | c << 32; t = f + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (e ~ (c & (d ~ e))) + K[j + 10] + w11
        b = (b + t) & M; u = g | g << 32
        f = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((g & h) | (a & (g | h)))) & M
        t = b | b << 32; t = e + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (d ~ (b & (c ~ d))) + K[j + 11] + w12
        a = (a + t) & M; u = f | f << 32
        e = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((f & g) | (h & (f | g)))) & M
        t = a | a << 32; t = d + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (c ~ (a & (b ~ c))) + K[j + 12] + w13
        h = (h + t) & M; u = e | e << 32
        d = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((e & f) | (g & (e | f)))) & M
        t = h | h << 32; t = c + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (b ~ (h & (a ~ b))) + K[j + 13] + w14
        g = (g + t) & M; u = d | d << 32
        c = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((d & e) | (f & (d | e)))) & M
        t = g | g << 32; t = b + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (a ~ (g & (h ~ a))) + K[j + 14] + w15
        f = (f + t) & M; u = c | c << 32
        b = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((c & d) | (e & (c | d)))) & M
        t = f | f << 32; t = a + ((t >> 6) ~ (t >> 11) ~ (t >> 25)) + (h ~ (f & (g ~ h))) + K[j + 15] + w16
        e = (e + t) & M; u = b | b << 32
        a = (t + ((u >> 2) ~ (u >> 13) ~ (u >> 22)) + ((b & c) | (d & (b | c)))) & M
        if j == 49 then break end
        t = w2 | w2 << 32; u = w15 | w15 << 32
        w1 = (w1 + ((t >> 7) ~ (t >> 18) ~ (w2 >> 3)) + w10 + ((u >> 17) ~ (u >> 19) ~ (w15 >> 10))) & M
        t = w3 | w3 << 32; u = w16 | w16 << 32
        w2 = (w2 + ((t >> 7) ~ (t >> 18) ~ (w3 >> 3)) + w11 + ((u >> 17) ~ (u >> 19) ~ (w16 >> 10))) & M
        t = w4 | w4 << 32; u = w1 | w1 << 32
        w3 = (w3 + ((t >> 7) ~ (t >> 18) ~ (w4 >> 3)) + w12 + ((u >> 17) ~ (u >> 19) ~ (w1 >> 10))) & M
        t = w5 | w5 << 32; u = w2 | w2 << 32
        w4 = (w4 + ((t >> 7) ~ (t >> 18) ~ (w5 >> 3)) + w13 + ((u >> 17) ~ (u >> 19) ~ (w2 >> 10))) & M
        t = w6 | w6 << 32; u = w3 | w3 << 32
        w5 = (w5 + ((t >> 7) ~ (t >> 18) ~ (w6 >> 3)) + w14 + ((u >> 17) ~ (u >> 19) ~ (w3 >> 10))) & M
        t = w7 | w7 << 32; u = w4 | w4 << 32
        w6 = (w6 + ((t >> 7) ~ (t >> 18) ~ (w7 >> 3)) + w15 + ((u >> 17) ~ (u >> 19) ~ (w4 >> 10))) & M
        t = w8 | w8 << 32; u = w5 | w5 << 32
        w7 = (w7 + ((t >> 7) ~ (t >> 18) ~ (w8 >> 3)) + w16 + ((u >> 17) ~ (u >> 19) ~ (w5 >> 10))) & M
        t = w9 | w9 << 32; u = w6 | w6 << 32
        w8 = (w8 + ((t >> 7) ~ (t >> 18) ~ (w9 >> 3)) + w1 + ((u >> 17) ~ (u >> 19) ~ (w6 >> 10))) & M
        t = w10 | w10 << 32; u = w7 | w7 << 32
        w9 = (w9 + ((t >> 7) ~ (t >> 18) ~ (w10 >> 3)) + w2 + ((u >> 17) ~ (u >> 19) ~ (w7 >> 10))) & M
        t = w11 | w11 << 32; u = w8 | w8 << 32
        w10 = (w10 + ((t >> 7) ~ (t >> 18) ~ (w11 >> 3)) + w3 + ((u >> 17) ~ (u >> 19) ~ (w8 >> 10))) & M
        t = w12 | w12 << 32; u = w9 | w9 << 32
        w11 = (w11 + ((t >> 7) ~ (t >> 18) ~ (w12 >> 3)) + w4 + ((u >> 17) ~ (u >> 19) ~ (w9 >> 10))) & M
        t = w13 | w13 << 32; u = w10 | w10 << 32
        w12 = (w12 + ((t >> 7) ~ (t >> 18) ~ (w13 >> 3)) + w5 + ((u >> 17) ~ (u >> 19) ~ (w10 >> 10))) & M
        t = w14 | w14 << 32; u = w11 | w11 << 32
        w13 = (w13 + ((t >> 7) ~ (t >> 18) ~ (w14 >> 3)) + w6 + ((u >> 17) ~ (u >> 19) ~ (w11 >> 10))) & M
        t = w15 | w15 << 32; u = w12 | w12 << 32
        w14 = (w14 + ((t >> 7) ~ (t >> 18) ~ (w15 >> 3)) + w7 + ((u >> 17) ~ (u >> 19) ~ (w12 >> 10))) & M
        t = w16 | w16 << 32; u = w13 | w13 << 32
        w15 = (w15 + ((t >> 7) ~ (t >> 18) ~ (w16 >> 3)) + w8 + ((u >> 17) ~ (u >> 19) ~ (w13 >> 10))) & M
        t = w1 | w1 << 32; u = w14 | w14 << 32
        w16 = (w16 + ((t >> 7) ~ (t >> 18) ~ (w1 >> 3)) + w9 + ((u >> 17) ~ (u >> 19) ~ (w14 >> 10))) & M
    end
    return (a0 + a) & M, (b0 + b) & M, (c0 + c) & M, (d0 + d) & M,
        (e0 + e) & M, (f0 + f) & M, (g0 + g) & M, (h0 + h) & M
end

-- Compresses the 64-byte block of s at pos into state H (in place).
local function compress(H, s, pos)
    H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8] =
        block(H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8], sunpack(BLOCK, s, pos))
end

-- Pads s, which follows `prefix` bytes already compressed into H, compresses it and returns
-- the eight hash words. Whole blocks are read from s itself; only the tail is copied to pad it.
local function finish(H, s, prefix)
    local len = #s
    local whole = len - len % 64
    for pos = 1, whole, 64 do compress(H, s, pos) end
    local tail = s:sub(whole + 1) .. "\128" .. srep("\0", (55 - len) % 64) .. spack(">I8", (prefix + len) * 8)
    for pos = 1, #tail, 64 do compress(H, tail, pos) end
    return H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
end

local function digestString(s)
    return spack(WORDS8, finish({unpack(H0)}, s, 0))
end

-- The state after one 64-byte block of the key, zero-padded, with every byte XORed with pad.
local function keyState(key, pad)
    local w = {sunpack(BLOCK, key .. srep("\0", 64 - #key))}
    for i = 1, 16 do w[i] = w[i] ~ pad end
    return {block(H0[1], H0[2], H0[3], H0[4], H0[5], H0[6], H0[7], H0[8], unpack(w, 1, 16))}
end

-- Inner and outer HMAC states after their 64-byte key blocks.
local function hmacStates(key)
    if #key > 64 then key = digestString(key) end
    return keyState(key, 0x36363636), keyState(key, 0x5c5c5c5c)
end

-- The HMAC as eight words. The outer message is the 32-byte inner hash after the 64-byte key
-- block, so it is one block: the hash, the 0x80 marker, zeros and the bit length 96 * 8.
local function hmacWords(data, inner, outer)
    local i1, i2, i3, i4, i5, i6, i7, i8 = finish({unpack(inner)}, data, 64)
    return block(outer[1], outer[2], outer[3], outer[4], outer[5], outer[6], outer[7], outer[8],
        i1, i2, i3, i4, i5, i6, i7, i8, 0x80000000, 0, 0, 0, 0, 0, 0, 768)
end

-- The digest as a string, for callers that work on strings.
local function digestRaw(data)
    return digestString(mapToStr(data or ""))
end

local function digest(data)
    return strToByteArr(digestRaw(data))
end

-- The HMAC as a string, for callers that work on strings (ecc.encrypt and ecc.decrypt).
local function hmacRaw(data, key)
    local inner, outer = hmacStates(mapToStr(key))
    return spack(WORDS8, hmacWords(mapToStr(data), inner, outer))
end

local function hmac(data, key)
    return strToByteArr(hmacRaw(data, key))
end

local function pbkdf2(pass, salt, iter, dklen)
    salt = mapToStr(salt)
    iter = tonumber(iter) or 1000
    dklen = tonumber(dklen) or 32
    local inner, outer = hmacStates(mapToStr(pass))
    local i1, i2, i3, i4, i5, i6, i7, i8 = unpack(inner)
    local o1, o2, o3, o4, o5, o6, o7, o8 = unpack(outer)
    local out = {}
    local index = 1
    local yielded = clock()

    while dklen > 0 do
        local u1, u2, u3, u4, u5, u6, u7, u8 = hmacWords(salt .. spack(">I4", index), inner, outer)
        local x1, x2, x3, x4, x5, x6, x7, x8 = u1, u2, u3, u4, u5, u6, u7, u8
        for j = 2, iter do
            -- U_j = HMAC(U_{j-1}): both hashes are single blocks of a 32-byte message after the
            -- 64-byte key block (see hmacWords), kept in words so the loop allocates nothing.
            u1, u2, u3, u4, u5, u6, u7, u8 = block(i1, i2, i3, i4, i5, i6, i7, i8,
                u1, u2, u3, u4, u5, u6, u7, u8, 0x80000000, 0, 0, 0, 0, 0, 0, 768)
            u1, u2, u3, u4, u5, u6, u7, u8 = block(o1, o2, o3, o4, o5, o6, o7, o8,
                u1, u2, u3, u4, u5, u6, u7, u8, 0x80000000, 0, 0, 0, 0, 0, 0, 768)
            x1, x2, x3, x4 = x1 ~ u1, x2 ~ u2, x3 ~ u3, x4 ~ u4
            x5, x6, x7, x8 = x5 ~ u5, x6 ~ u6, x7 ~ u7, x8 ~ u8
            -- Yield after about 50 ms of CPU so other programs and events keep running.
            if j % 16 == 0 and clock() - yielded > 0.05 then
                sleep(0)
                yielded = clock()
            end
        end
        local clen = dklen > 32 and 32 or dklen
        out[#out + 1] = spack(WORDS8, x1, x2, x3, x4, x5, x6, x7, x8):sub(1, clen)
        dklen = dklen - clen
        index = index + 1
    end

    return strToByteArr(concat(out))
end

sha256.digest = digest
sha256.digestRaw = digestRaw
sha256.hmac = hmac
sha256.hmacRaw = hmacRaw
sha256.pbkdf2 = pbkdf2
return sha256
