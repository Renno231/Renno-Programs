
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
-- Add timing jitter. os.time() only changes once per game tick, so counting calls between its
-- changes (the ComputerCraft approach) yields almost nothing here; os.clock() is this machine's
-- CPU time in nanoseconds and varies from run to run. The address separates computers that
-- booted from copies of the same disk, /.random included.
local computer = require("computer")
feed(computer.address())
feed(tostring(computer.uptime()))
local samples = {}
for i = 1, 64 do
    for _ = 1, i % 7 do feed(tostring({})) end
    samples[i] = ("%.9f"):format(os.clock())
end
feed(table.concat(samples, "|"))
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

-- /.random carries entropy across reboots. Each load reads it and immediately writes the next
-- value (save above), so no boot reuses a state; output doesn't need to touch the disk.
local function newRandom()
    feed("random")
    feed(tostring(os.time()))
    feed(("%.9f"):format(os.clock()))
    feed(tostring({}))
    digest()

    local result = sha256.hmac("out", entropy)
    entropy = tostring(sha256.digest(entropy))

    return result
end

random.seed = seed
random.save = save
random.random = newRandom
return random