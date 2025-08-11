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

-- Helper function to save screens data
function screens._save()
    -- Convert to save format
    local data = {
        screens = {},
        main = _main
    }
    
    for address, label in pairs(_screens) do
        table.insert(data.screens, {name = label, address = address})
    end
    
    -- Use handler.write to save the data
    return handler.write("screens.cb", data)
end

-- Helper function to load screens data
function screens._load()
    -- Clear current data
    _screens = {}
    _labels = {}
    _main = nil
    
    -- Use handler.read to load the data
    return handler.read("screens.cb", function(data)
        -- Decode the CBOR data
        local decoded = require("cbor").decode(data)
        
        -- Populate screens and labels
        for _, screen in ipairs(decoded.screens) do
            _screens[screen.address] = screen.name
            _labels[screen.name] = screen.address
        end
        
        -- Set main screen
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
    -- Check if it's an address
    if _screens[labelOrAddress] then
        return true, _screens[labelOrAddress]
    end
    
    -- Check if it's a label
    if _labels[labelOrAddress] then
        return true, _labels[labelOrAddress]
    end
    
    -- Not found
    return false, string.format("%s not resolved", labelOrAddress)
end

-- Function to register a screen
function screens.register(address, label)
    -- Check if address is already registered
    if _screens[address] then
        return false, "Address already registered"
    end
    
    -- Check if label is already used
    if _labels[label] then
        return false, "Label already in use"
    end
    
    -- Register the screen
    _screens[address] = label
    _labels[label] = address
    
    return screens._save()
end

-- Function to unregister a screen
function screens.unregister(labelOrAddress)
    local resolved, result = screens.resolve(labelOrAddress)
    if not resolved then
        return false, result
    end
    
    -- Determine if result is an address or label
    local address, label
    if _screens[result] then
        address = result
        label = _screens[result]
    elseif _labels[result] then
        address = _labels[result]
        label = result
    end
    
    -- Remove from screens and labels
    _screens[address] = nil
    _labels[label] = nil
    
    -- If it was the main screen, unset it
    if _main == address then
        _main = nil
    end
    
    return screens._save()
end

-- Function to set the main screen
function screens.setMain(labelOrAddress)
    local resolved, result = screens.resolve(labelOrAddress)
    if not resolved then
        return false, result
    end
    
    -- Determine if result is an address or label
    local address
    if _screens[result] then
        address = result
    elseif _labels[result] then
        address = _labels[result]
    end
    
    -- Save the previous main screen address
    local lastMainAddress = _main
    
    -- Set the new main screen
    _main = address
    screens._save()
    
    return true, lastMainAddress
end

-- Function to get the main screen
function screens.getMain()
    if not _main then
        return false
    end
    
    -- Get the label for the main screen address
    local label = _screens[_main]
    if not label then
        -- Main screen address doesn't exist in screens anymore
        _main = nil
        screens._save()
        return false
    end
    
    return true, label, _main
end

-- Function to get the currently bound screen
function screens.getCurrentScreen()
    local gpu = require("component").gpu
    if not gpu then
        return false, "No GPU component"
    end
    
    -- Get the address of the currently bound screen
    local address = gpu.getScreen()
    if not address then
        return false, "No screen bound to GPU"
    end
    
    -- Try to resolve the address to a label
    local resolved, result = screens.resolve(address)
    if resolved then
        -- The result is the label
        return true, result, address
    else
        -- The screen is not registered, but we can still return the address
        return false, "Screen not registered", address
    end
end

-- Function to bind to a screen
function screens.bindTo(labelOrAddress, resetScreen)
    local gpu = component.gpu
    if not gpu then
        return false, "No GPU component"
    end
    
    -- If labelOrAddress is nil and there's a main screen, bind to main
    if not labelOrAddress then
        local success, label, address = screens.getMain()
        if success then
            if component.proxy(address) then
                gpu.bind(address, resetScreen)
                return true, label, address
            else
                return false, string.format("component not found %s", address)
            end
        else
            return false, "No main screen set"
        end
    end
    
    -- Resolve the screen
    local resolved, result = screens.resolve(labelOrAddress)
    if not resolved then
        return false, result
    end
    
    -- Determine if result is an address or label
    local address
    if _screens[result] then
        address = result
    elseif _labels[result] then
        address = _labels[result]
    end
    
    -- Bind to the screen
    if component.proxy(address) then
        gpu.bind(address, resetScreen)
    else
        return false, string.format("component not found %s", address)
    end
    
    return true, _screens[address], address
end

-- Function to rename a screen
function screens.rename(labelOrAddress, newLabel)
    -- Check if new label is already used
    if _labels[newLabel] then
        return false, "New label already in use"
    end
    
    -- Resolve the screen
    local resolved, result = screens.resolve(labelOrAddress)
    if not resolved then
        return false, result
    end
    
    -- Determine if result is an address or label
    local address, oldLabel
    if _screens[result] then
        address = result
        oldLabel = _screens[result]
    elseif _labels[result] then
        address = _labels[result]
        oldLabel = result
    end
    
    -- Update the label in both mappings
    _screens[address] = newLabel
    _labels[oldLabel] = nil
    _labels[newLabel] = address
    
    screens._save()
    return true
end

return screens