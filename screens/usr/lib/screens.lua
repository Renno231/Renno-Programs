-- screens.lua (library)

local screens = {}
local dataio = require("dataio")
local handler = dataio.handler("screens")
local component = require("component")

-- Configure CBOR serialization
handler.serializationLib("cbor", "encode", "decode")

-- Internal data structures
local _screens = {} -- Maps address to label
local _labels = {}  -- Maps label to address (reverse lookup)
local _main = nil  -- Address of the main screen

-- for tracking running programs
screens._runningThreads = screens._runningThreads or {}
screens._runningPrograms = screens._runningPrograms or {}

-- Helper function to save screens data
function screens._save()
    local data = { screens = {}, main = _main }
    for address, label in pairs(_screens) do
        table.insert(data.screens, {name = label, address = address})
    end
    return handler.write("screens.cb", data)
end

-- Helper function to load screens data
function screens._load()
    _screens = {}
    _labels = {}
    _main = nil
    return handler.read("screens.cb", function(data)
        if not data or data == "" then return end
        local decoded = require("cbor").decode(data)
        for _, screen in ipairs(decoded.screens) do
            _screens[screen.address] = screen.name
            _labels[screen.name] = screen.address
        end
        _main = decoded.main
    end)
end

-- Initialize by loading data
screens:_load()

-- Function to get a list of screen components
function screens.getScreens()
    local result = {}
    for address, label in pairs(_screens) do
        table.insert(result, {address = address, label = label})
    end
    return result
end

-- Function to resolve a label or address
function screens.resolve(labelOrAddress)
    if _screens[labelOrAddress] then return true, _screens[labelOrAddress] end
    if _labels[labelOrAddress] then return true, _labels[labelOrAddress] end
    return false, string.format("%s not resolved", labelOrAddress)
end

-- Function to register a screen
function screens.register(address, label)
    if _screens[address] then return false, "Address already registered" end
    if _labels[label] then return false, "Label already in use" end
    _screens[address] = label
    _labels[label] = address
    return screens._save()
end

-- Function to unregister a screen
function screens.unregister(labelOrAddress)
    local resolved, result = screens.resolve(labelOrAddress)
    if not resolved then return false, result end
    local address, label
    if _screens[result] then address = result; label = _screens[result]
    elseif _labels[result] then address = _labels[result]; label = result end
    _screens[address] = nil
    _labels[label] = nil
    if _main == address then _main = nil end
    return screens._save()
end

-- Function to set the main screen
function screens.setMain(labelOrAddress)
    local resolved, result = screens.resolve(labelOrAddress)
    if not resolved then return false, result end
    local address
    if _screens[result] then address = result elseif _labels[result] then address = _labels[result] end
    local lastMainAddress = _main
    _main = address
    screens._save()
    return true, lastMainAddress
end

-- Function to get the main screen
function screens.getMain()
    if not _main then return false end
    local label = _screens[_main]
    if not label then _main = nil; screens._save(); return false end
    return true, label, _main
end

-- Function to get the currently bound screen
function screens.getCurrentScreen()
    local gpu = require("component").gpu
    if not gpu then return false, "No GPU component" end
    local address = gpu.getScreen()
    if not address then return false, "No screen bound to GPU" end
    local resolved, result = screens.resolve(address)
    if resolved then return true, result, address
    else return false, "Screen not registered", address end
end

-- Function to bind to a screen
function screens.bindTo(labelOrAddress, resetScreen)
    local gpu = component.gpu
    if not gpu then return false, "No GPU component" end
    if not labelOrAddress then
        local current = gpu.getScreen()
        local success, label, address = screens.getMain()
        if success then
            if address == current then
                return false, "screen already bound"
            elseif component.proxy(address) then
                gpu.bind(address, resetScreen); return true, label, address
            else
                return false, string.format("component not found %s", address)
            end
        else return false, "No main screen set" end
    end
    local resolved, result = screens.resolve(labelOrAddress)
    if not resolved then return false, result end
    local address
    if _screens[result] then address = result elseif _labels[result] then address = _labels[result] end
    local current = gpu.getScreen()
    if current == address then
        return false, "screen already bound"
    elseif component.proxy(address) then
        gpu.bind(address, resetScreen)
    else
        return false, string.format("component not found %s", address) end
    return true, _screens[address], address
end

-- Function to rename a screen
function screens.rename(labelOrAddress, newLabel)
    if _labels[newLabel] then return false, "New label already in use" end
    local resolved, result = screens.resolve(labelOrAddress)
    if not resolved then return false, result end
    local address, oldLabel
    if _screens[result] then address = result; oldLabel = _screens[result]
    elseif _labels[result] then address = _labels[result]; oldLabel = result end
    _screens[address] = newLabel
    _labels[oldLabel] = nil
    _labels[newLabel] = address
    screens._save()
    return true
end

local screenEventTypes = {
    screen_resized = true, touch = true, drag = true,
    drop = true, scroll = true, walk = true
}
local keyboardEventTypes = {
    key_down = true, key_up = true, clipboard = true
}
-- /usr/lib/screens.lua
local function runOnScreen(labelOrAddress, programPath, options, ...)
    local thread = require("thread")
    local shell = require("shell")
    local component = require("component")
    local computer = require("computer")

    -- options = options or {}
    -- local minSleepTime = tonumber(options.minSleepTime) -- Force minimum sleep duration
    -- local sleepMultiplier = tonumber(options.sleepMultiplier) or 1

    local resolved, result = screens.resolve(labelOrAddress)
    if not resolved then return false, result end
    local address
    if _screens[result] then address = result elseif _labels[result] then address = _labels[result] end

    local programArgs = {...}

    local programThread = thread.create(function()
        local t = thread.current()
        local mt = getmetatable(t)
        
        local screenProxy = component.proxy(address)
        local cachedKeyboardAddress = nil
        local lastKeyboardCheckTime = 0
        local KEYBOARD_CHECK_INTERVAL = 60 -- Check once a minute

        local function updateKeyboardCache()
            if screenProxy then
                local keyboards = {screenProxy.getKeyboards()}
                cachedKeyboardAddress = keyboards[1]
            end
            lastKeyboardCheckTime = computer.uptime()
        end

        local originalPull = mt.process.data.pull
        local newPull = function(_, timeout)
                local deadline = timeout and (computer.uptime() + timeout) or nil
                
                while true do
                -- Update keyboard cache periodically
                if computer.uptime() - lastKeyboardCheckTime > KEYBOARD_CHECK_INTERVAL then
                    updateKeyboardCache()
                end
                
                -- Release GPU before pulling (cooperative yield point)
                if timeout == nil or timeout > 0 then
                    screens.bindTo()
                end
                
                local remaining = deadline and math.max(0, deadline - computer.uptime()) or nil
                local eventData = table.pack(originalPull(_, remaining))
                local eventName = eventData[1]
                
                -- Determine if this event belongs to us
                local isOurEvent = false
                if deadline and computer.uptime() >= deadline then
                    isOurEvent = true  -- Timeout expired
                elseif type(eventName) ~= "string" then
                    isOurEvent = true  -- Timeout signal or internal event
                elseif screenEventTypes[eventName] then
                    isOurEvent = (eventData[2] == address)
                elseif keyboardEventTypes[eventName] then
                    isOurEvent = (cachedKeyboardAddress and eventData[2] == cachedKeyboardAddress)
                end
                
                if isOurEvent then
                    -- Reacquire GPU and return
                    if timeout == nil or timeout > 0 then
                    screens.bindTo(address)
                    end
                    return table.unpack(eventData, 1, eventData.n)
                end
                
                -- Not our event; loop and pull again
                -- Timeout check for loop termination
                if deadline and computer.uptime() >= deadline then
                    screens.bindTo(address)  -- Restore GPU on timeout
                    return nil  -- Standard timeout return
                end
            end
        end
        mt.process.data.pull = newPull

        updateKeyboardCache()
        local success, label = screens.bindTo(address)
        if not success then
            mt.process.data.pull = originalPull
            return false, label
        end

        local oldResolution = {component.gpu.getResolution()}
        local oldForeground = component.gpu.getForeground()
        local oldBackground = component.gpu.getBackground()

        -- Run the program using the standard shell.
        local results = {shell.execute(programPath, nil, table.unpack(programArgs))}

        -- CLEANUP
        mt.process.data.pull = originalPull
        screens.bindTo(address, false)
        component.gpu.setForeground(oldForeground)
        component.gpu.setBackground(oldBackground)
        component.gpu.setResolution(table.unpack(oldResolution))
        local hasMain, _, mainAddress = screens.getMain()
        if hasMain and mainAddress ~= address then
            screens.bindTo(mainAddress, false)
        end

        if not results[1] then
            return false, "Child process crashed"
        end
        return table.unpack(results)
    end)

    programThread:detach()
    return true, programThread
end

-- Function to stop a program running on a specific screen
function screens.stopProgram(labelOrAddress)
    local resolved, result = screens.resolve(labelOrAddress)
    if not resolved then return false, result end
    local address
    if _screens[result] then address = result elseif _labels[result] then address = _labels[result] end

    if screens._runningThreads and screens._runningThreads[address] then
        local thread = screens._runningThreads[address]
        if thread:status() ~= "dead" then
            thread:kill()
            screens._runningThreads[address] = nil
            return true
        else
            screens._runningThreads[address] = nil
            return false, "Program already stopped"
        end
    else
        return false, "No program running on this screen"
    end
end

-- Function to list running programs
function screens.listRunningPrograms()
    local hasMain, mainLabel, mainAddress = screens.getMain()
    local registeredScreens = screens.getScreens()
    local computer = require("computer")
    local result = {}

    for _, screen in ipairs(registeredScreens) do
        if screens._runningThreads and screens._runningThreads[screen.address] then
            local marker = ""
            if hasMain and screen.address == mainAddress then marker = " (main)" end
            local thread = screens._runningThreads[screen.address]
            local status = thread:status()
            local programInfo = screens._runningPrograms[screen.address]
            local runtime = programInfo and math.floor(computer.uptime() - programInfo.startTime) or 0

            table.insert(result, {
                label = screen.label,
                address = screen.address,
                marker = marker,
                status = status,
                program = programInfo and programInfo.program or "Unknown",
                runtime = runtime
            })
        end
    end
    return result
end

-- Override runOnScreen to track threads
screens.runOnScreen = function(labelOrAddress, programPath, options, ...)
    local resolved, result = screens.resolve(labelOrAddress)
    if not resolved then return false, result end
    local address
    if _screens[result] then address = result elseif _labels[result] then address = _labels[result] end

    if screens._runningThreads[address] then
        local oldThread = screens._runningThreads[address]
        if oldThread:status() ~= "dead" then
            oldThread:kill()  -- Force termination
        end
        -- Don't nil the entry here; thread_exit listener will clean up
    end
    -- Call the local implementation function to create the thread.
    -- It now correctly returns the thread object.
    local success, programThread = runOnScreen(labelOrAddress, programPath, options, ...)

    if success then
        -- Store the returned thread object.
        screens._runningThreads[address] = programThread
        screens._runningPrograms[address] = {
            program = programPath,
            startTime = require("computer").uptime()
        }

        require("event").listen("thread_exit", function(eventName, exitedThread)
            -- If the thread that exited is the one this listener is responsible for...
            if tostring(exitedThread) == tostring(programThread) then
                screens._runningThreads[address] = nil
                screens._runningPrograms[address] = nil
                return false
            end
        end)
    end
    return success, programThread
end

return screens