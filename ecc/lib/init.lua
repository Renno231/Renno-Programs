-- Elliptic Curve Cryptography in OpenComputers

---- Update (Feb 13 2024) by Renno231
-- made library OPPM compatible and implemented lazy-loading
---- Update (January 15 2024) by Renno231
-- added key derivatative from string (password)
-- added symmetrical key generation method
---- Update (January 12 2024) by Renno231
-- ported to OpenComputers
-- added backup bit32 functions
-- added asymmetrical encrypt/decrypt (thanks to PG231)
---- Update (Jun  7 2023)
-- Fix string inputs not working on signatures
-- Switch internal byte arrays to strings on most places
-- Improve entropy gathering by using counting
-- Other general improvements to syntax
---- Update (Jun  4 2021)
-- Fix compatibility with CraftOS-PC
---- Update (Jul 30 2020)
-- Make randomModQ and use it instead of hashing from random.random()
---- Update (Feb 10 2020)
-- Make a more robust encoding/decoding implementation
---- Update (Dec 30 2019)
-- Fix rng not accumulating entropy from loop
-- (older versions should be fine from other sources + stored in disk)
---- Update (Dec 28 2019)
-- Slightly better integer multiplication and squaring
-- Fix global variable declarations in modQ division and verify() (no security concerns)
-- Small tweaks from SquidDev's illuaminate (https://github.com/SquidDev/illuaminate/)
local os = require("os")
local fs = require"filesystem"

local ecc = {_loaded = {}}

local function mapToStr(t)
    return type(t) == "table" and string.char(table.unpack(t)) or tostring(t)
end

local bit32 = require"bit32"
local byteTableMT = {
    __tostring = mapToStr,
    __index = {
        toHex = function(self) return ("%02x"):rep(#self):format(table.unpack(self)) end,
        isEqual = function(self, t)
            if type(t) ~= "table" then return false end
            if #self ~= #t then return false end
            local ret = 0
            for i = 1, #self do
                ret = bit32.bor(ret, bit32.bxor(self[i], t[i]))
            end
            return ret == 0
        end
    }
}

local function strToByteArr(s)
    return setmetatable({s:byte(1, -1)}, byteTableMT)
end

-- actual cryptography

local function getNonceFromEpoch()
    local nonce = {}
    local epoch = os.time()
    for _ = 1, 12 do
        nonce[#nonce + 1] = math.floor(epoch) % 256
        epoch = epoch / 256
        epoch = epoch - epoch % 1
    end
    
    return nonce
end

local function encrypt(data, key)
    key = mapToStr(key)
    local encKey = ecc.sha256.hmac("encKey", key)
    local macKey = ecc.sha256.hmac("macKey", key)
    local nonce = getNonceFromEpoch()
    local ciphertext = ecc.chacha20.crypt(mapToStr(data), encKey, nonce)

    local result = nonce
    for i = 1, #ciphertext do
        result[#result + 1] = ciphertext[i]
    end
    local mac = ecc.sha256.hmac(result, macKey)
    for i = 1, #mac do
        result[#result + 1] = mac[i]
    end

    return setmetatable(result, byteTableMT)
end

local function decrypt(data, key)
    data = mapToStr(data)
    key = mapToStr(key)
    local encKey = ecc.sha256.hmac("encKey", key)
    local macKey = ecc.sha256.hmac("macKey", key)
    local mac = ecc.sha256.hmac(data:sub(1, -33), macKey)
    assert(mac:isEqual(strToByteArr(data:sub(-32))), "invalid mac")
    local result = ecc.chacha20.crypt(data:sub(13, -33), encKey, data:sub(1, 12))

    return setmetatable(result, byteTableMT)
end

local function key(seed)
    return (seed and ecc.modq.hashModQ(mapToStr(seed)) or ecc.modq.randomModQ()):encode()
end

local function keypair(seed)
    local x = (seed and ecc.modq.hashModQ(mapToStr(seed)) or ecc.modq.randomModQ())
    local Y = ecc.curve.G * x

    local privateKey = x:encode()
    local publicKey = Y:encode()

    return privateKey, publicKey
end

local function exchange(privateKey, publicKey)
    local x = ecc.modq.decodeModQ(mapToStr(privateKey))
    local Y = ecc.curve.pointDecode(mapToStr(publicKey))

    local Z = Y * x

    local sharedSecret = ecc.sha256.digest(Z:encode())

    return sharedSecret
end

local function asymEncrypt(publicKey, data)
    local sk, pk = keypair()
    return mapToStr(pk) .. mapToStr(encrypt(data, exchange(sk, publicKey)))
end

local function asymDecrypt(privateKey, data)
-- assert the strings have the correct length etc
    local pk = data:sub(1, 22)
    local ctx = data:sub(23)
    return decrypt(ctx, exchange(privateKey, pk))
end

local function sign(privateKey, message)
    local x = ecc.modq.decodeModQ(mapToStr(privateKey))
    local k = ecc.modq.randomModQ()
    local R = ecc.curve.G * k
    local e = ecc.modq.hashModQ(mapToStr(message) .. tostring(R))
    local s = k - x * e

    e = e:encode()
    s = s:encode()

    local result = e
    for i = 1, #s do
        result[#result + 1] = s[i]
    end

    return setmetatable(result, byteTableMT)
end

local function verify(publicKey, message, signature)
    signature = mapToStr(signature)
    local Y = ecc.curve.pointDecode(mapToStr(publicKey))
    local e = ecc.modq.decodeModQ(signature:sub(1, 21))
    local s = ecc.modq.decodeModQ(signature:sub(22))
    local Rv = ecc.curve.G * s + Y * e
    local ev = ecc.modq.hashModQ(mapToStr(message) .. tostring(Rv))

    return ev == e
end

local function deriveKeyFromPassword(password, salt, iterations) --doesn't work with 'public' keys since they are 22 long
    -- Implement or call a KDF like PBKDF2 with SHA-256
    -- 'salt' should be a unique value for each password, can be stored alongside the encrypted data
    local derivedKey = ecc.sha256.pbkdf2(password, salt or ecc.random.random(), iterations or 10000, 21) --iterations, keyLength)
    return derivedKey
end

local function findFile(fileName, startDir)
    checkArg(1, fileName, "string")
    startDir = startDir or "/" -- Default start directory is root
    
    local dirsToVisit = startDir:find(":") and string.gmatch(startDir, "[^:]+") or {startDir}
    while #dirsToVisit > 0 do
        local currentDir = table.remove(dirsToVisit, 1) -- Get and remove the first element
        if fs.exists(fs.concat(currentDir, fileName)) then
            return fs.concat(currentDir, fileName)
        end
        for entry in fs.list(currentDir) do
            local fullPath = fs.concat(currentDir, entry)
            if fs.isDirectory(fullPath) then
                table.insert(dirsToVisit, fullPath) -- Add directory to the list to visit
            else
                -- Check if the file matches the fileName with any extension
                if entry == fileName or entry:match("^" .. fileName .. "%..+$") then
                    return fullPath
                end
            end
        end
    end
    
    return false, "file not found"
end

local selfPath = findFile("ecc", "/usr")
if not selfPath then
    selfPath = findFile("ecc") --more expensive search
    if not selfPath then
        error("ECC unable to locate sub-libraries")
    end
end

local subPath = selfPath.."/sublibraries/"
if not fs.exists(subPath) then
    error("ECC unable to locate sub-libraries at "..subPath)
end

local available = {
    chacha20 = true,
    sha256 = true,
    random = true,
    encrypt = encrypt,
    decrypt = decrypt,
    aencrypt = asymEncrypt, --asymmetrical
    adecrypt = asymDecrypt, --asymmetrical
    key = key, --single key
    keypair = keypair,
    keyFromPassword = deriveKeyFromPassword,
    exchange = exchange,
    sign = sign,
    verify = verify,
}

local libraries = {
    arith = true,
    chacha20 = true,
    curve = true,
    modp = true,
    modq = true,
    random = true,
    sha256 = true
}

setmetatable(ecc, {
    __index = function(self, value)
        if self._loaded[value] then
            return self._loaded[value]
        elseif libraries[value] then
            self._loaded[value] = loadfile(subPath..value..".lua")(subPath..value..".lua", ecc, mapToStr, strToByteArr, byteTableMT)
            return self._loaded[value]
        elseif value == "unload" then
            return function() 
                for i, _ in pairs (self._loaded) do
                    self._loaded[i] = nil
                end
            end
        elseif value == "load" then

        else
            local usable = available[value]
            if type(usable) == 'boolean' then
                usable = ecc.value
            end
            return usable
        end
    end,
    __metatable = "offlimits"
})

return ecc