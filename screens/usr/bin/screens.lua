local screens = require("screens")
local component = require("component")
local computer = require("computer")
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
        -- Check if the screen component still exists
        local proxy = component.proxy(screen.address)
        if not proxy then
            -- Screen is no longer available, unregister it
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
    -- Get all screen components using the filter
    local allScreens = {}
    for address in component.list("screen") do
        table.insert(allScreens, address)
    end
    
    -- Get registered screens
    local registeredScreens = screens.getScreens()
    
    -- Register unresolved screens numerically
    local nextIndex = 1
    for _, screenAddress in ipairs(allScreens) do
        -- Check if screen is already registered using resolve function
        local resolved, _ = screens.resolve(screenAddress)
        if not resolved then
            -- Find an available label
            local label
            repeat
                label = "s" .. nextIndex
                nextIndex = nextIndex + 1
                -- Check if label is already in use
                local labelResolved, _ = screens.resolve(label)
            until not labelResolved
            
            -- Register the screen
            screens.register(screenAddress, label)
        end
    end
    
    -- Refresh the list of registered screens
    registeredScreens = screens.getScreens()
    
    -- Get the main screen if it exists
    local hasMain, mainLabel, mainAddress = screens.getMain()
    
    -- If only one screen, set it as main and exit
    if #registeredScreens == 1 then
        screens.setMain(registeredScreens[1].address)
        print("Only one screen found, set as main: " .. registeredScreens[1].label)
        return
    end
    
    -- Display the list of screens on the main screen without clearing
    if hasMain then
        screens.bindTo(mainAddress, false)  -- Don't clear the screen
        print("Registered Screens:")
        listScreens()  -- Use our existing function to list screens
    end
    
    -- Display screen labels on each screen
    local fails = {}
    local w,h =25,8
    for _, screen in ipairs(registeredScreens) do
        if hasMain and screen.address == mainAddress then
            -- Do nothing for the main screen
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
    
    -- If there are multiple screens, bind back to the main screen
    if #registeredScreens > 1 and hasMain then
        screens.bindTo(mainAddress)  -- Don't clear when returning to main
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
    
    -- Create a filter that accepts touch and interrupted events
    local function filter(name, ...)
        return name == "touch" or name == "interrupted"
    end
    
    -- Wait for a touch or interrupted event
    local eventData = {event.pullFiltered(filter)}
    if not eventData or #eventData < 1 then
        print("Error: Invalid event received")
        return
    end
    
    -- Check if it's an interrupted event
    if eventData[1] == "interrupted" then
        print("Registration cancelled")
        return
    end
    
    -- Extract the screen address (second element in touch event)
    local screenAddress = eventData[2]
    
    -- Check if the screen is already registered
    local resolved, result = screens.resolve(screenAddress)
    if resolved then
        print("Screen is already registered as: " .. result)
        return
    end
    print(("Touch detected on %s"):format(screenAddress))
    -- Ask for a name
    term.write("Enter a name for this screen (leave empty for auto-generated name): ")
    local input = io.read()
    if input == false then
        return print("Registration cancelled")
    end
    -- If input is empty, generate a name
    local label
    if input == "" then
        -- Generate a name using the same convention as in registerScreens
        local nextIndex = 1
        repeat
            label = "s" .. nextIndex
            nextIndex = nextIndex + 1
            -- Check if label is already in use
            local labelResolved, _ = screens.resolve(label)
        until not labelResolved
    else
        label = input
    end
    
    -- Register the screen
    local success, result = screens.register(screenAddress, label)
    if success then
        print("Screen registered successfully as: " .. label)
    else
        print("Failed to register screen: " .. result)
    end
end

-- Parse command line arguments
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
    end
    setMain(args[2])
elseif command == "rename" then
    if not args[2] or not args[3] then
        print("Error: Missing label/address or new label")
        printUsage()
        listScreens()
    end
    renameScreen(args[2], args[3])
elseif command == "cleanup" then
    cleanupScreens()
elseif command == "onTouch" then
    onTouch()
elseif command == "help" or not command then
    printUsage()
    listScreens()
else
    print("Error: Unknown command: " .. command)
    printUsage()
    listScreens()
end