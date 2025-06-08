-- data handler library e.g. dhandler = require"dataio".new(directoryName, serializationLibraryName, serializationLibrary.serialize, serializationLibrary.deserialize)
local fs = require"filesystem"
local dataio = {}
dataio._root = "/usr/data/"
dataio.root = function(newRoot)
    local oldRoot = dataio._root
    if type(newRoot) == "string" then
        dataio._root = newRoot
    elseif newRoot ~= nil then
        return false, "invalid root type for ".. tostring(newRoot)
    end
    return oldRoot
end

dataio.__handlers = {}

local function dataHandler(handleName)
    checkArg(1, handleName, "string")
    if dataio.__handlers[handleName] then
        return dataio.__handlers[handleName]
    end
    
    if not fs.exists(fs.concat(dataio.root(), handleName)) then
        fs.makeDirectory(fs.concat(dataio.root(), handleName))
    end
    local dataHandler = {_handleName = handleName, _root = dataio.root(), _serialLib = "serialization", _serialMethod = "serialize", _deserialMethod = "unserialize"}
    dataHandler.getHandle = function()
        return dataHandler._handleName
    end

    dataHandler.getPath = function()
        return fs.concat(dataHandler._root, dataHandler._handleName)
    end

    dataHandler.serializationLib = function(name, serial, deserial, fileType)
        checkArg(1, name, "string", "nil") checkArg(1, serial, "string", "nil") checkArg(1, deserial, "string", "nil")
        local oldLib, oldSMethod, oldDMethod = dataHandler._serialLib, dataHandler._serialLib, dataHandler._deserialMethod
        if name and serial and deserial then
            dataHandler._serialLib, dataHandler._serialMethod, dataHandler._deserialMethod = name, serial, deserial
        end
        return oldLib, oldSMethod, oldDMethod
    end

    dataHandler.read = function(path, onReadCallback)
        local file, err = io.open(fs.concat(dataio.root(), dataHandler.getHandle(), path), "r")
        if file == nil then return false, err end
        local data = file:read("a*")
        file:close()
        return onReadCallback and onReadCallback(data) or require(dataHandler._serialLib)[dataHandler._deserialMethod](data)
    end

    dataHandler.readRaw = function(path, onReadCallback)
        local file, err = io.open(fs.concat(dataio.root(), dataHandler.getHandle(), path), "r")
        if file == nil then return false, err end
        local success, readErr = pcall(onReadCallback, file)
        file:close()
        return success, readErr    
    end

    dataHandler.write = function(path, contents)
        checkArg(2, contents, "function", "string", "table", "userdata", "nil")
        local newPath = fs.concat(dataio.root(), dataHandler.getHandle(), path)
        if not fs.exists(fs.path(newPath)) then
            fs.makeDirectory(fs.path(newPath))
        end
        local file, err = io.open(newPath, "w")
        if not file then
            return false, "Failed to open file for writing: " .. (err or "unknown error")
        end
        
        local success, writeErr = pcall(function()
            if type(contents) == "function" then
                contents(file)
            elseif type(contents) == "table" or type(contents) == "userdata" then
                file:write(require(dataHandler._serialLib)[dataHandler._serialMethod](contents))
            else
                file:write(contents)
            end
        end)
        
        file:close() -- Always close the file
        
        if not success then
            return false, "Error during write operation: " .. tostring(writeErr)
        end
        return true
    end
    dataio.__handlers[handleName] = dataHandler
    return dataHandler
end

dataio.handler = dataHandler

return dataio