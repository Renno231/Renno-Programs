local path, ecc, mapToStr, lazyLoad, strToByteArr, byteTableMT = ...
if not (ecc and mapToStr and lazyLoad and strToByteArr and byteTableMT) then
    error((path or "sha256.lua").." is a private sublibrary of ecc, use the ecc library instead")
end

-- SHA-256, HMAC and PBKDF2 on Lua 5.3 integers.
-- Same interface and outputs as the ComputerCraft version by Anavrins
-- (http://pastebin.com/6UV4qfNF) that this replaces.
local sha256 = {}
local spack, sunpack, schar, sbyte, srep = string.pack, string.unpack, string.char, string.byte, string.rep
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

local BLOCK = ">I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4"
local WORDS8 = ">I4I4I4I4I4I4I4I4"
local w = {} -- message schedule, reused

-- Compresses the 64-byte block of s at pos into state H (in place).
-- Rotations leave bits above 32 and sums may wrap; only the low 32 bits of each sum matter,
-- so values are masked once when they are stored.
local function compress(H, s, pos)
    w[1], w[2], w[3], w[4], w[5], w[6], w[7], w[8],
    w[9], w[10], w[11], w[12], w[13], w[14], w[15], w[16] = sunpack(BLOCK, s, pos)
    for j = 17, 64 do
        local x, y = w[j - 15], w[j - 2]
        local s0 = ((x >> 7) | (x << 25)) ~ ((x >> 18) | (x << 14)) ~ (x >> 3)
        local s1 = ((y >> 17) | (y << 15)) ~ ((y >> 19) | (y << 13)) ~ (y >> 10)
        w[j] = (w[j - 16] + s0 + w[j - 7] + s1) & 0xffffffff
    end
    local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for j = 1, 64 do
        local temp1 = h + (((e >> 6) | (e << 26)) ~ ((e >> 11) | (e << 21)) ~ ((e >> 25) | (e << 7)))
            + ((e & f) ~ (~e & g)) + K[j] + w[j]
        local temp2 = (((a >> 2) | (a << 30)) ~ ((a >> 13) | (a << 19)) ~ ((a >> 22) | (a << 10)))
            + ((a & b) ~ (a & c) ~ (b & c))
        h, g, f, e, d, c, b = g, f, e, (d + temp1) & 0xffffffff, c, b, a
        a = (temp1 + temp2) & 0xffffffff
    end
    H[1] = (H[1] + a) & 0xffffffff
    H[2] = (H[2] + b) & 0xffffffff
    H[3] = (H[3] + c) & 0xffffffff
    H[4] = (H[4] + d) & 0xffffffff
    H[5] = (H[5] + e) & 0xffffffff
    H[6] = (H[6] + f) & 0xffffffff
    H[7] = (H[7] + g) & 0xffffffff
    H[8] = (H[8] + h) & 0xffffffff
end

-- Pads s, which follows `prefix` bytes already compressed into H, compresses it and returns the hash.
local function finish(H, s, prefix)
    local len = #s
    s = s .. "\128" .. srep("\0", (55 - len) % 64) .. spack(">I8", (prefix + len) * 8)
    for pos = 1, #s, 64 do compress(H, s, pos) end
    return spack(WORDS8, H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
end

local function digestString(s)
    return finish({unpack(H0)}, s, 0)
end

local function xorPad(key, pad)
    local out = {sbyte(key, 1, -1)}
    for i = 1, #out do out[i] = out[i] ~ pad end
    return schar(unpack(out)) .. srep(schar(pad), 64 - #key)
end

-- Inner and outer HMAC states after their 64-byte key blocks.
local function hmacStates(key)
    if #key > 64 then key = digestString(key) end
    local inner, outer = {unpack(H0)}, {unpack(H0)}
    compress(inner, xorPad(key, 0x36), 1)
    compress(outer, xorPad(key, 0x5c), 1)
    return inner, outer
end

local function hmacString(data, inner, outer)
    return finish({unpack(outer)}, finish({unpack(inner)}, data, 64), 64)
end

local function digest(data)
    return strToByteArr(digestString(mapToStr(data or "")))
end

local function hmac(data, key)
    local inner, outer = hmacStates(mapToStr(key))
    return strToByteArr(hmacString(mapToStr(data), inner, outer))
end

local function pbkdf2(pass, salt, iter, dklen)
    salt = mapToStr(salt)
    iter = tonumber(iter) or 1000
    dklen = tonumber(dklen) or 32
    local inner, outer = hmacStates(mapToStr(pass))
    local out = {}
    local block = 1
    local yielded = clock()

    while dklen > 0 do
        local u = hmacString(salt .. spack(">I4", block), inner, outer)
        local x1, x2, x3, x4, x5, x6, x7, x8 = sunpack(WORDS8, u)
        for j = 2, iter do
            u = hmacString(u, inner, outer)
            local y1, y2, y3, y4, y5, y6, y7, y8 = sunpack(WORDS8, u)
            x1, x2, x3, x4 = x1 ~ y1, x2 ~ y2, x3 ~ y3, x4 ~ y4
            x5, x6, x7, x8 = x5 ~ y5, x6 ~ y6, x7 ~ y7, x8 ~ y8
            -- Yield after about 50 ms of CPU so other programs and events keep running.
            if j % 16 == 0 and clock() - yielded > 0.05 then
                sleep(0)
                yielded = clock()
            end
        end
        local clen = dklen > 32 and 32 or dklen
        out[#out + 1] = spack(WORDS8, x1, x2, x3, x4, x5, x6, x7, x8):sub(1, clen)
        dklen = dklen - clen
        block = block + 1
    end

    return strToByteArr(concat(out))
end

sha256.digest = digest
sha256.hmac = hmac
sha256.pbkdf2 = pbkdf2
return sha256
