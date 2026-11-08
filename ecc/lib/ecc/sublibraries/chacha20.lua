local path, ecc, mapToStr, lazyLoad, strToByteArr, byteTableMT = ...
if not (ecc and mapToStr and lazyLoad and strToByteArr and byteTableMT) then
    error((path or "chacha20.lua").."is a private sublibrary of ecc, use the ecc library instead")
end

-- ChaCha20 on Lua 5.3 integers.
-- Same interface and outputs as the ComputerCraft version by Anavrins
-- (http://pastebin.com/GPzf9JSa) that this replaces.
local chacha20 = {}
local spack, sunpack, sbyte, schar = string.pack, string.unpack, string.byte, string.char
local concat, unpack, tonumber, assert = table.concat, table.unpack, tonumber, assert
local clock, sleep = os.clock, os.sleep
local M = 0xffffffff
local WORDS16 = "<I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4"

-- Keystream words for one block of state st.
local function hashBlock(st, rounds)
    local x1, x2, x3, x4, x5, x6, x7, x8 = st[1], st[2], st[3], st[4], st[5], st[6], st[7], st[8]
    local x9, x10, x11, x12, x13, x14, x15, x16 = st[9], st[10], st[11], st[12], st[13], st[14], st[15], st[16]
    for i = 1, rounds do
        if i % 2 == 1 then
            x1 = (x1 + x5) & M; x13 = x13 ~ x1; x13 = ((x13 << 16) | (x13 >> 16)) & M
            x9 = (x9 + x13) & M; x5 = x5 ~ x9; x5 = ((x5 << 12) | (x5 >> 20)) & M
            x1 = (x1 + x5) & M; x13 = x13 ~ x1; x13 = ((x13 << 8) | (x13 >> 24)) & M
            x9 = (x9 + x13) & M; x5 = x5 ~ x9; x5 = ((x5 << 7) | (x5 >> 25)) & M
            x2 = (x2 + x6) & M; x14 = x14 ~ x2; x14 = ((x14 << 16) | (x14 >> 16)) & M
            x10 = (x10 + x14) & M; x6 = x6 ~ x10; x6 = ((x6 << 12) | (x6 >> 20)) & M
            x2 = (x2 + x6) & M; x14 = x14 ~ x2; x14 = ((x14 << 8) | (x14 >> 24)) & M
            x10 = (x10 + x14) & M; x6 = x6 ~ x10; x6 = ((x6 << 7) | (x6 >> 25)) & M
            x3 = (x3 + x7) & M; x15 = x15 ~ x3; x15 = ((x15 << 16) | (x15 >> 16)) & M
            x11 = (x11 + x15) & M; x7 = x7 ~ x11; x7 = ((x7 << 12) | (x7 >> 20)) & M
            x3 = (x3 + x7) & M; x15 = x15 ~ x3; x15 = ((x15 << 8) | (x15 >> 24)) & M
            x11 = (x11 + x15) & M; x7 = x7 ~ x11; x7 = ((x7 << 7) | (x7 >> 25)) & M
            x4 = (x4 + x8) & M; x16 = x16 ~ x4; x16 = ((x16 << 16) | (x16 >> 16)) & M
            x12 = (x12 + x16) & M; x8 = x8 ~ x12; x8 = ((x8 << 12) | (x8 >> 20)) & M
            x4 = (x4 + x8) & M; x16 = x16 ~ x4; x16 = ((x16 << 8) | (x16 >> 24)) & M
            x12 = (x12 + x16) & M; x8 = x8 ~ x12; x8 = ((x8 << 7) | (x8 >> 25)) & M
        else
            x1 = (x1 + x6) & M; x16 = x16 ~ x1; x16 = ((x16 << 16) | (x16 >> 16)) & M
            x11 = (x11 + x16) & M; x6 = x6 ~ x11; x6 = ((x6 << 12) | (x6 >> 20)) & M
            x1 = (x1 + x6) & M; x16 = x16 ~ x1; x16 = ((x16 << 8) | (x16 >> 24)) & M
            x11 = (x11 + x16) & M; x6 = x6 ~ x11; x6 = ((x6 << 7) | (x6 >> 25)) & M
            x2 = (x2 + x7) & M; x13 = x13 ~ x2; x13 = ((x13 << 16) | (x13 >> 16)) & M
            x12 = (x12 + x13) & M; x7 = x7 ~ x12; x7 = ((x7 << 12) | (x7 >> 20)) & M
            x2 = (x2 + x7) & M; x13 = x13 ~ x2; x13 = ((x13 << 8) | (x13 >> 24)) & M
            x12 = (x12 + x13) & M; x7 = x7 ~ x12; x7 = ((x7 << 7) | (x7 >> 25)) & M
            x3 = (x3 + x8) & M; x14 = x14 ~ x3; x14 = ((x14 << 16) | (x14 >> 16)) & M
            x9 = (x9 + x14) & M; x8 = x8 ~ x9; x8 = ((x8 << 12) | (x8 >> 20)) & M
            x3 = (x3 + x8) & M; x14 = x14 ~ x3; x14 = ((x14 << 8) | (x14 >> 24)) & M
            x9 = (x9 + x14) & M; x8 = x8 ~ x9; x8 = ((x8 << 7) | (x8 >> 25)) & M
            x4 = (x4 + x5) & M; x15 = x15 ~ x4; x15 = ((x15 << 16) | (x15 >> 16)) & M
            x10 = (x10 + x15) & M; x5 = x5 ~ x10; x5 = ((x5 << 12) | (x5 >> 20)) & M
            x4 = (x4 + x5) & M; x15 = x15 ~ x4; x15 = ((x15 << 8) | (x15 >> 24)) & M
            x10 = (x10 + x15) & M; x5 = x5 ~ x10; x5 = ((x5 << 7) | (x5 >> 25)) & M
        end
    end
    return (x1 + st[1]) & M, (x2 + st[2]) & M, (x3 + st[3]) & M, (x4 + st[4]) & M,
        (x5 + st[5]) & M, (x6 + st[6]) & M, (x7 + st[7]) & M, (x8 + st[8]) & M,
        (x9 + st[9]) & M, (x10 + st[10]) & M, (x11 + st[11]) & M, (x12 + st[12]) & M,
        (x13 + st[13]) & M, (x14 + st[14]) & M, (x15 + st[15]) & M, (x16 + st[16]) & M
end

local function crypt(data, key, nonce, cntr, round)
    data = mapToStr(data)
    key = mapToStr(key)
    nonce = mapToStr(nonce)
    assert(#key == 16 or #key == 32, "ChaCha20: Invalid key length ("..#key.."), must be 16 or 32")
    assert(#nonce == 12, "ChaCha20: Invalid nonce length ("..#nonce.."), must be 12")
    cntr = tonumber(cntr) or 1
    round = tonumber(round) or 20

    local k = #key == 32 and key or key .. key
    local st = {sunpack("<I4I4I4I4", #key == 32 and "expand 32-byte k" or "expand 16-byte k")}
    st[5], st[6], st[7], st[8], st[9], st[10], st[11], st[12] = sunpack("<I4I4I4I4I4I4I4I4", k)
    st[13] = cntr
    st[14], st[15], st[16] = sunpack("<I4I4I4", nonce)
    st[17] = nil -- sunpack's next-position return

    local out = {}
    local len = #data
    local yielded = clock()
    for pos = 1, len, 64 do
        local k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15, k16 = hashBlock(st, round)
        st[13] = (st[13] + 1) & M
        if pos + 63 <= len then
            local d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13, d14, d15, d16 = sunpack(WORDS16, data, pos)
            out[#out + 1] = spack(WORDS16, d1 ~ k1, d2 ~ k2, d3 ~ k3, d4 ~ k4, d5 ~ k5, d6 ~ k6, d7 ~ k7, d8 ~ k8,
                d9 ~ k9, d10 ~ k10, d11 ~ k11, d12 ~ k12, d13 ~ k13, d14 ~ k14, d15 ~ k15, d16 ~ k16)
        else
            local ks = {sbyte(spack(WORDS16, k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14, k15, k16), 1, -1)}
            local b = {sbyte(data, pos, len)}
            for j = 1, #b do b[j] = b[j] ~ ks[j] end
            out[#out + 1] = schar(unpack(b))
        end
        -- Yield after about 50 ms of CPU so other programs and events keep running.
        if clock() - yielded > 0.05 then
            sleep(0)
            yielded = clock()
        end
    end
    return strToByteArr(concat(out))
end

chacha20.crypt = crypt
return chacha20
