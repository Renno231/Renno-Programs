local screens = require("screens")
local component = require("component")
local shell = require("shell")
local term = require("term")
local event = require("event")
local io = require("io")

local function printUsage()
    print("Usage:")
    print("  screens register - Register all available screens")
    print("  screens getMain - Show the main screen")
    print("  screens setMain <labelOrAddress> - Set the main screen")
    print("  screens rename <labelOrAddress> <newLabel> - Rename a screen")
    print("  screens cleanup - Remove screens that are no longer available")
    print("  screens onTouch - Register the next touched screen")
    print("  screens run <screenLabel> [<option>...] <program> [args...]")
    print("    Options:")
    print("      --min-sleep-time=<seconds>  Minimum sleep duration")
    print("      --sleep-multiplier=<factor>  Scale all sleep calls")
    print("  screens start <screenLabel> [<option>...] <program> [args...]")
    print("  screens stop <screenLabel> - Stop a program running on a specific screen")
    print("  screens stopAll - Stops all running programs on all screens")
    print("  screens running - List running programs on screens")
    print("  screens list - List registered screens")
    print("  screens reload - reloads the screens library from file")
    print("  screens help - Show this help message")
    print()
    print("Registered Screens:")
end

local function listScreens()
    local registeredScreens = screens.getScreens()
    local hasMain, mainLabel, mainAddress = screens.getMain()
    if #registeredScreens == 0 then
        print("  No screens registered")
        return
    end
    for _, screen in ipairs(registeredScreens) do
        local marker = ""
        if hasMain and screen.address == mainAddress then
            marker = " (main)"
        end
        print("  " .. screen.label .. " - " .. screen.address .. marker)
    end
end

local function cleanupScreens()
    local registeredScreens = screens.getScreens()
    local removedCount = 0
    for _, screen in ipairs(registeredScreens) do
        local proxy = component.proxy(screen.address)
        if not proxy then
            local success, result = screens.unregister(screen.address)
            if success then
                print("Unregistered screen: " .. screen.label .. " - " .. screen.address)
                removedCount = removedCount + 1
            else
                print("Failed to unregister screen: " .. screen.label .. " - " .. screen.address .. ": " .. result)
            end
        end
    end
    if removedCount == 0 then
        print("No screens needed to be removed")
    else
        print("Removed " .. removedCount .. " screen(s) that are no longer available")
    end
end

local function registerScreens()
    local allScreens = {}
    for address in component.list("screen") do
        table.insert(allScreens, address)
    end
    local registeredScreens = screens.getScreens()
    local nextIndex = 1
    for _, screenAddress in ipairs(allScreens) do
        local resolved, _ = screens.resolve(screenAddress)
        if not resolved then
            local label
            repeat
                label = "s" .. nextIndex
                nextIndex = nextIndex + 1
                local labelResolved, _ = screens.resolve(label)
            until not labelResolved
            screens.register(screenAddress, label)
        end
    end
    registeredScreens = screens.getScreens()
    local hasMain, mainLabel, mainAddress = screens.getMain()
    if #registeredScreens == 1 then
        screens.setMain(registeredScreens[1].address)
        print("Only one screen found, set as main: " .. registeredScreens[1].label)
        return
    end
    if hasMain then
        screens.bindTo(mainAddress, false)
        print("Registered Screens:")
        listScreens()
    end
    local fails = {}
    local w,h =25,8
    for _, screen in ipairs(registeredScreens) do
        if hasMain and screen.address == mainAddress then
        else
            if screens.bindTo(screen.address) then
                component.gpu.setResolution(w,h)
                component.gpu.fill(1,1,w,h," ")
                local text = screen.label
                local x = math.floor((w - #text) / 2) + 1
                local y = math.floor(h / 2)
                component.gpu.set(x, y, text)
            else
                table.insert(fails, ("Failed to bind %s (%s)"):format(screen.label, screen.address))
            end
        end
    end
    if #registeredScreens > 1 and hasMain then
        screens.bindTo(mainAddress)
        component.gpu.setResolution(component.gpu.getResolution())
        for i,v in pairs (fails) do
            print(v)
        end
    end
end

local function getMain()
    local hasMain, mainLabel, mainAddress = screens.getMain()
    if hasMain then
        print("Main screen: " .. mainLabel .. " - " .. mainAddress)
    else
        print("No main screen set")
    end
end

local function setMain(labelOrAddress)
    local success, lastMainLabel = screens.setMain(labelOrAddress)
    if success then
        if lastMainLabel then
            print("Main screen changed from " .. lastMainLabel .. " to " .. labelOrAddress)
        else
            print("Main screen set to " .. labelOrAddress)
        end
    else
        print("Failed to set main screen: " .. lastMainLabel)
    end
end

local function renameScreen(labelOrAddress, newLabel)
    local success, result = screens.rename(labelOrAddress, newLabel)
    if success then
        print("Screen renamed successfully")
    else
        print("Failed to rename screen: " .. result)
    end
end

local function onTouch()
    print("Please touch a screen to register it (Ctrl+C to cancel)...")
    local function filter(name, ...) return name == "touch" or name == "interrupted" end
    local eventData = {event.pullFiltered(filter)}
    if not eventData or #eventData < 1 then
        print("Error: Invalid event received")
        return
    end
    if eventData[1] == "interrupted" then
        print("Registration cancelled")
        return
    end
    local screenAddress = eventData[2]
    local resolved, result = screens.resolve(screenAddress)
    if resolved then
        print("Screen is already registered as: " .. result)
        return
    end
    print(("Touch detected on %s"):format(screenAddress))
    term.write("Enter a name for this screen (leave empty for auto-generated name): ")
    local input = io.read()
    if input == false then return print("Registration cancelled") end
    local label
    if input == "" then
        local nextIndex = 1
        repeat
            label = "s" .. nextIndex
            nextIndex = nextIndex + 1
            local labelResolved, _ = screens.resolve(label)
        until not labelResolved
    else
        label = input
    end
    local success, result = screens.register(screenAddress, label)
    if success then
        print("Screen registered successfully as: " .. label)
    else
        print("Failed to register screen: " .. result)
    end
end

local function listRunningPrograms()
    local runningPrograms = screens.listRunningPrograms()
    print("Running Programs:")
    if #runningPrograms == 0 then
        print("  No programs running on registered screens")
        return
    end
    for _, program in ipairs(runningPrograms) do
        print("  " .. program.label .. " - " .. program.address .. program.marker .. ": " .. program.program .. " (running for " .. program.runtime .. "s, status: " .. program.status .. ")")
    end
end

-- COMMAND PARSING
local args = shell.parse(...)
local command = args[1]

if command == "register" then
    registerScreens()
elseif command == "getMain" then
    getMain()
elseif command == "setMain" then
    if not args[2] then
        print("Error: Missing label or address")
        printUsage()
        listScreens()
    else
        setMain(args[2])
    end
elseif command == "rename" then
    if not args[2] or not args[3] then
        print("Error: Missing label/address or new label")
        printUsage()
        listScreens()
    else
        renameScreen(args[2], args[3])
    end
elseif command == "cleanup" then
    cleanupScreens()
elseif command == "onTouch" then
    onTouch()
elseif command == "run" or command == "start" then
    if not args[2] then
        print("Error: Missing screen label")
        printUsage()
        listScreens()
    else
        local rawArgs = {...}
        local screenLabel = args[2]
        
        -- Find the program name in the raw args (first non-option after screenLabel)
        local programIndex = nil
        local programName = nil
        
        for i = 3, #rawArgs do
            local token = tostring(rawArgs[i])
            if token:sub(1,1)~="-" then
                programIndex = i
                programName = token
                break
            end
        end
        
        if not programName then
            print("Error: Missing program path")
            printUsage()
            return
        end
        
        -- Build the options substring (everything before program name)
        local optionsCmd = {}
        for i = 3, programIndex - 1 do
            table.insert(optionsCmd, rawArgs[i])
        end
        -- Parse options using shell.parse (it returns BOTH args and options)
        local dummyArgs, runOptions = shell.parse(table.unpack(optionsCmd))
        
        -- Parse program args using shell.parse
        local programArgs = shell.parse(table.concat(rawArgs, " ", programIndex+1))
        if programArgs[1] == "" then programArgs[1] = nil end
        
        runOptions.minSleepTime = runOptions['min-sleep-time']
        runOptions.sleepMultiplier = runOptions['sleep-multiplier']
        local oV = {require("tty").getViewport()}
        local success, result = screens.runOnScreen(screenLabel, programName, runOptions, table.unpack(programArgs, 1, programArgs.n))
        require("tty").setViewport(table.unpack(oV))
        if success then
            print("Started " .. programName .. " on screen " .. screenLabel)
        else
            print("Failed to start program: " .. result)
        end
    end
elseif command == "stop" then
    if not args[2] then
        print("Error: Missing screen label")
        printUsage()
        listScreens()
    else
        local success, result = screens.stopProgram(args[2])
        if success then
            print("Stopped program on screen: " .. args[2])
        else
            print("Failed to stop program: " .. result)
        end
    end
elseif command == "stopAll" then
    local runningPrograms = screens.listRunningPrograms()
    if #runningPrograms == 0 then 
        return print("No programs running at this time")
    end
    for _, program in ipairs(runningPrograms) do
        local success, result = screens.stopProgram(program.address)
        if success then
            print("Stopped program on screen: " .. program.label)
        else
            print("Failed to stop program: " .. result)
        end
    end
elseif command == "running" then
    listRunningPrograms()
elseif command == "list" then
    listScreens()
elseif command == "reload" then
    package.loaded.screens = nil
    require("screens")
    print("Screens library reloaded")
elseif command == "help" or not command then
    printUsage()
    listScreens()
else
    print("Error: Unknown command: " .. command)
    printUsage()
    listScreens()
end