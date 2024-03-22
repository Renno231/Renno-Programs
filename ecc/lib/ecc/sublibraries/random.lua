
local path, ecc, mapToStr, lazyLoad, strToByteArr, byteTableMT = ...
if not (ecc and mapToStr and lazyLoad and strToByteArr and byteTableMT) then
    error((path or "random.lua").." is a private sublibrary of ecc, use the ecc library instead")
end
local fs = require"filesystem"
local io = require("io")
local sha256 = lazyLoad("sha256")

-- random.lua - Random Byte Generator
local random = {}
local entropy = ""
local accumulator = ""
local entropyPath = "/.random"

local function feed(data)
    accumulator = accumulator .. (data or "")
end

local function digest()
    entropy = tostring(sha256.digest(entropy .. accumulator))
    accumulator = ""
end

if fs.exists(entropyPath) then
    local entropyFile = io.open(entropyPath, "rb")
    feed(entropyFile:read("*a"))
    entropyFile:close()
end

-- Add context.
feed("init")
feed(tostring(math.random(1, 2^31 - 1)))
feed("|")
feed(tostring(math.random(1, 2^31 - 1)))
feed("|")
feed(tostring(math.random(1, 2^4)))
feed("|")
feed(tostring(os.time()))
feed("|")
feed(tostring({}))
feed(tostring({}))
digest()
feed(tostring(os.time()))
digest()
-- Add entropy by counting.
local countTable = {}
local countf = assert(load("local e=require('os').time return function()return{" .. ("e(),"):rep(256):sub(1,-2) .. "}end"))()
for i = 1, 300 do
    while true do
        local t = countf()
        local t1 = t[1]
        if t1 ~= t[256] then
            for j = 1, 256 do
                if t1 ~= t[j] then
                    countTable[i] = j - 1
                    break
                end
            end
        end
        break
    end
end

feed(mapToStr(countTable))
digest()

local function save()
    feed("save")
    feed(tostring(os.time()))
    feed(tostring({}))
    digest()

    local entropyFile = io.open(entropyPath, "wb")
    entropyFile:write(tostring(sha256.hmac("save", entropy)))
    entropy = tostring(sha256.digest(entropy))
    entropyFile:close()
end
save()

local function seed(data)
    feed("seed")
    feed(tostring(os.time()))
    feed(tostring({}))
    feed(mapToStr(data))
    digest()
    save()
end

local function newRandom()
    feed("random")
    feed(tostring(os.time()))
    feed(tostring({}))
    digest()
    save()

    local result = sha256.hmac("out", entropy)
    entropy = tostring(sha256.digest(entropy))

    return result
end

random.seed = seed
random.save = save
random.random = newRandom
return random