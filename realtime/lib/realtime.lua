local tempFile = "/tmp/.time"
local fs = require("filesystem")
local computer = require"computer"

local lastPolledTime = 0
local lastTime = nil
local function lastChanged(filepath)
    return (fs.lastModified(filepath) / 1000) - 18000
end

local function sync()
    local time = io.open(tempFile, "w")
    -- time:write()
    time:close()
    lastPolledTime = computer.uptime()
    lastTime = lastChanged(tempFile)
end
sync()

local function getRealTime(format)
    return os.date(format or "*t", computer.uptime() - lastPolledTime + lastTime)
end

local function getRealTimeRaw()
    return computer.uptime() - lastPolledTime + lastTime
end


return {getRealTime = getRealTime, getRealTimeRaw = getRealTimeRaw, tempFile = tempFile, sync = sync}