local tnet = {}
local connections = {}
local listeners = {}
local event = require("event")
local computer = require("computer")
local component = require("component")
local pack = table.pack

-- Packet type lookup table for shorter messages
local pTypeRev, pTypes = {}, {
    ['c'] = "connect",
    ['a'] = "connected", 
    ['d'] = "disconnect",
    ['s'] = "serialLib",
    ['m'] = "data"
}

local function makeId()
    -- 4 chars from this computer
    local base, n, id = computer.address():sub(-8,-5), 0
    repeat
        id = base .. string.format("%04x", n % 0x10000)
        n = n + 1
    until not connections[id]
    return id
end

for t, f in pairs (pTypes) do
    pTypeRev[f] = t
end
-- Connection object
local Connection = {}
Connection.__index = Connection
local function newConnection(fields)
    return setmetatable({
        modem        = fields.modem,
        address      = fields.address,
        port         = fields.port,
        wake         = fields.wake,
        sys          = fields.sys or "unknown",
        id           = fields.id,
        expectations = {},
        default_callback = nil,
        connection_timeout = nil,
        last_activity = computer.uptime(),
        on_error     = nil,
        serial       = nil,
        connected    = fields.connected or false,
        msg_id       = 0,
        wakeValidator = fields.wakeValidator
    }, Connection)
end

-- Timeout checker - only checks existing connections
local function startTimeoutChecker()
    if tnet.timeoutClock then return end
    tnet.timeoutClock = event.timer(1, function()
        local now = computer.uptime()
        for _, conn in pairs(connections) do
            -- Check connection-level timeout
            if conn.connection_timeout and conn.last_activity then
                if now - conn.last_activity > conn.connection_timeout then
                    if conn.on_error then
                        pcall(conn.on_error, "Connection timeout")
                    end
                    conn:close()
                end
            end

            -- Check message-specific timeouts
            for msg_id, cb in pairs(conn.expectations) do
                if cb.timeout and (now - cb.registered > cb.timeout) then
                    if conn.on_error then
                        pcall(conn.on_error, "Timeout waiting for response: " .. msg_id)
                    end
                    conn.expectations[msg_id] = nil
                end
            end

            -- Check default callback timeout
            if conn.default_callback and conn.default_callback.timeout then
                if now - conn.default_callback.registered > conn.default_callback.timeout then
                    if conn.on_error then
                        pcall(conn.on_error, "Default callback timeout")
                    end
                    conn.default_callback = nil
                end
            end

            if conn._fragBuffer and conn._fragBuffer.lastFragTime then
                if now - conn._fragBuffer.lastFragTime > 10 then
                    if conn.on_error then
                        pcall(conn.on_error, "Fragment buffer timeout (incomplete data)")
                    end
                    conn._fragBuffer = nil
                end
            end
        end
    end, math.huge)
end

local function initRouter()
    if tnet.routerEventID then return end
    tnet.routerFunction = function(_, selfAddress, senderAddress, localPort, dist, wake, ninfo, msg, ...)
        wake, ninfo, msg = wake or "", ninfo or "", msg or ""
        local ninfo_parts = {}
        for part in string.gmatch(ninfo, "[^,]+") do
            table.insert(ninfo_parts, part)
        end
        
        if #ninfo_parts < 4 then
            return
        end
        
        local sys_name, conn_id, msg_id, packet_type, frag, maxFrag = table.unpack(ninfo_parts)
        packet_type = pTypes[packet_type] or packet_type
        local args = pack(...)
        if packet_type == "connect" and listeners[localPort] then
            local listener = listeners[localPort]
            if listener.wakeValidator then
                local valid, result = pcall(listener.wakeValidator, wake)
                if not valid or not result then
                    return
                end
            end
            
            local conn = newConnection({
                modem   = component.modem,
                address = senderAddress,
                port    = localPort,
                wake    = wake,
                sys     = sys_name,
                id      = conn_id,
                connected = true,          -- because server side is already live
                wakeValidator = listener.wakeValidator
            })
            
            connections[conn_id] = conn
            local ack_ninfo = table.concat({conn.sys or "server", conn.id, "0", pTypeRev["connected"]}, ",")
            pcall(conn.modem.send, senderAddress, localPort, wake, ack_ninfo)
            if listener.callback then
                pcall(listener.callback, conn)
            end
            return
        end
        
        local conn = connections[conn_id]
        if conn and conn.address == senderAddress and conn.sys == sys_name then
            if conn.wakeValidator then
                local valid, result = pcall(conn.wakeValidator, wake)
                if not valid or not result then
                    return
                end
            end
            
            if packet_type == "connected" then
                conn.connected = true
            elseif packet_type == "disconnect" then
                conn:close()
            elseif packet_type == "serialLib" then
                conn.serial = {
                    lib = msg,
                    encode = args[1],
                    decode = args[2]
                }
            elseif packet_type == "data" then
                if frag and maxFrag then
                    frag, maxFrag = tonumber(frag), tonumber(maxFrag)
                    local fBuffer = conn._fragBuffer or {fragCount = 0}
                    conn._fragBuffer = fBuffer
                    fBuffer.lastFragTime = computer.uptime()
                    if not fBuffer[frag] then
                        fBuffer[frag] = args[1]
                        fBuffer.fragCount = fBuffer.fragCount + 1
                    end
                    if fBuffer.fragCount == maxFrag then
                        conn:handleMessage(msg_id, msg, table.concat(fBuffer))
                        conn._fragBuffer = nil
                    end
                else
                    conn:handleMessage(msg_id, msg, table.unpack(args,1,args.n))
                end
            end
        else
        end
    end
    tnet.routerEventID = event.listen("modem_message", tnet.routerFunction)
end

function Connection:handleMessage(msg_id, msg, ...)
    self.last_activity = computer.uptime()
    local args = pack(...)

    -- Handle serialization
    if self.serial then
        local gotLibrary, serialLib = pcall(require, self.serial.lib)
        if gotLibrary then
            local success, data = pcall(serialLib[self.serial.decode], args[1])
            if success and data.msg and data.args then
                msg, args = data.msg, data.args
            else
                if self.on_error then
                    pcall(self.on_error, "Deserialization error: " .. tostring(data))
                end
                return
            end
        else
            if self.on_error then
                pcall(self.on_error, "Serial library error: " .. tostring(serialLib))
            end
            return
        end
    end

    -- Handle expected messages
    local cb_data = self.expectations[msg_id] or self.expectations[msg]
    if cb_data then
        -- Check timeout
        if cb_data.timeout and (computer.uptime() - cb_data.registered > cb_data.timeout) then
            self.expectations[msg_id] = nil
            self.expectations[msg] = nil
            return
        end

        -- Execute callback
        local success, err = pcall(cb_data.callback, self, msg, table.unpack(args,1,args.n))
        if not success and self.on_error then
            pcall(self.on_error, "Callback error (" .. msg .. "): " .. tostring(err))
        end
        
        -- Remove one-time expectations
        if not cb_data.persistent then
            self.expectations[msg_id] = nil
            self.expectations[msg] = nil
        end
    elseif self.default_callback then
        -- Check default timeout
        if self.default_callback.timeout and (computer.uptime() - self.default_callback.registered > self.default_callback.timeout) then
            self.default_callback = nil
            return
        end

        -- Execute default callback
        local success, err = pcall(self.default_callback.callback, self, msg, table.unpack(args,1,args.n))
        if not success and self.on_error then
            pcall(self.on_error, "Default callback error: " .. tostring(err))
        end
    end
end

function Connection:expect(arg1, arg2, arg3, arg4)
    if type(arg1) == "function" then
        self.default_callback = {
            callback = arg1,
            timeout = arg2,
            registered = computer.uptime()
        }
    else
        self.expectations[arg1] = {
            callback = arg2,
            timeout = arg3,
            registered = computer.uptime(),
            persistent = arg4 or false
        }
    end
end

function Connection:setTimeout(timeout)
    self.connection_timeout = timeout
end

function Connection:onError(callback)
    self.on_error = callback
end

function Connection:setWakeValidator(validator)
    self.wakeValidator = validator
end

function Connection:send(msg, ...)
    if not self.connected then
        if self.on_error then
            pcall(self.on_error, "Cannot send: not connected")
        end
        return nil
    end
    
    self.msg_id = self.msg_id + 1
    local args = pack(...)
    if self.serial then
        local gotLibrary, serialLib = pcall(require, self.serial.lib)
        if gotLibrary then
            local success, data = pcall(serialLib[self.serial.encode], {
                msg = msg,
                args = args
            })
            if success then
                args = {data}
            else
                if self.on_error then
                    pcall(self.on_error, "Serialization error: " .. tostring(data))
                end
                return nil
            end
        else
            if self.on_error then
                pcall(self.on_error, "Serial library error: " .. tostring(serialLib))
            end
            return nil
        end
    end
    -- Send message
    local ninfo, single = table.concat({self.sys, self.id, self.msg_id, pTypeRev["data"]}, ","), true
    local success, failed
    if self.serial then --fragmentation only with serialization set
        local dataMax = 8192 - (#self.wake + #ninfo + #msg + 20) -- extra 20 bits just in case
        local dataSize = #args[1]+2
        if dataMax < dataSize then
            single = false
            local totalFrags = math.ceil(dataSize / dataMax)
            for cFrag = 1, totalFrags do
                success, failed = pcall(self.modem.send, self.address, self.port, self.wake,
                                        ninfo..","..tostring(cFrag)..","..tostring(totalFrags), msg, args[1]:sub((cFrag-1) * dataMax + 1, cFrag * dataMax))
                if not success then break end
            end
        end
    end
    if single then
        success, failed = pcall(self.modem.send, self.address, self.port, self.wake, ninfo, msg, table.unpack(args,1,args.n))
    end
    if not success then
        if self.on_error then
            pcall(self.on_error, "Send failed" .. failed)
        end
        return nil
    end
    return self.msg_id
end 

function Connection:init(timeout)
    timeout = timeout or 1
    local start_time = computer.uptime()
    
    local ninfo = table.concat({self.sys, self.id, "0", pTypeRev["connect"]}, ",")
    pcall(self.modem.open, self.port)
    pcall(self.modem.send, self.address, self.port, self.wake, ninfo)
    
    -- local loop_count = 0
    while computer.uptime() - start_time < timeout do
        -- loop_count = loop_count + 1
        if self.connected then
            return true
        end
        os.sleep()
    end
    return false, "no response"
end

function Connection:close(quiet)
    if self.connected and not quiet then
        local ninfo = table.concat({self.sys, self.id, "0", pTypeRev["disconnect"]}, ",")
        pcall(self.modem.send, self.address, self.port, self.wake, ninfo)
    end
    self.default_callback = nil
    connections[self.id] = nil
    self.connected = false
end

function Connection:serialLib(lib, encode, decode)
    self.serial = {
        lib = lib,
        encode = encode,
        decode = decode
    }
    if self.connected then
        local ninfo = table.concat({self.sys, self.id, "0", pTypeRev["serialLib"]}, ",")
        pcall(self.modem.send, self.address, self.port, self.wake, ninfo, lib, encode, decode)
    end
end

-- Public API
function tnet.connect(address, port, wake, sys, conn_id, wakeValidator)
    local modem = component.modem
    if not modem then
        error("No modem component found")
    end
    
    local conn = newConnection({
        modem   = modem,
        address = address,
        port    = port,
        wake    = wake or computer.address(),
        sys     = sys or "unknown",
        id      = conn_id or makeId(),
        wakeValidator = wakeValidator
    })

    connections[conn.id] = conn
    
    -- Initialize router and timeout checker if needed
    if not tnet.routerEventID then initRouter() end
    if not tnet.timeoutClock then startTimeoutChecker() end
    
    return conn
end

function tnet.listen(port, callback, wakeValidator)
    local modem = component.modem
    if not modem then
        return false, ("No modem component found")
    end
    
    if listeners[port] then
        return false, ("Already listening on port " .. port)
    end
    
    modem.open(port)

    listeners[port] = {
        callback = callback,
        wakeValidator = wakeValidator
    }
    
    if not tnet.routerEventID then 
        initRouter() 
    end
    if not tnet.timeoutClock then 
        startTimeoutChecker() 
    end
    
    return true
end

-- multiplexer is a function that takes wake message and returns a sub-port, sub-port being an identifier for routing to callbacks from 1 port listener, can be a string
function tnet.multiplex(port, multiplexer, options)
    options = options or {}
    local listeners = {}
    local connections = {}  -- Track active connections
    local listening = false
    
    -- Internal connection handler with error handling
    local function handleConnection(conn)
        -- Track connection for cleanup
        connections[conn.id] = conn
        
        -- Override close to remove from tracking
        local originalClose = conn.close
        conn.close = function(self, quiet)
            connections[self.id] = nil
            originalClose(self, quiet)
        end
        
        -- Set default error handler if none exists
        if not conn.on_error then
            conn:onError(function(err)
                print("Multiplexer error:", err)
            end)
        end
        
        -- Safely get sub-port
        local success, subPort = pcall(multiplexer, conn.wake)
        if not success then
            pcall(conn.on_error, "Multiplexer error: " .. subPort)
            conn:close()
            return
        end
        
        -- Check if we have a listener for this sub-port
        if not subPort or not listeners[subPort] then
            pcall(conn.on_error, "No listener for subPort: " .. (subPort or "nil"))
            conn:close()
            return
        end
        
        -- Check wake validator if present
        local listener = listeners[subPort]
        if listener.wakeValidator then
            local valid, result = pcall(listener.wakeValidator, conn.wake)
            if not valid or not result then
                pcall(conn.on_error, "Wake validation failed for subPort: " .. subPort)
                conn:close()
                return
            end
        end
        
        -- Route to listener with error handling
        local routeSuccess, routeErr = pcall(listener.callback, conn)
        if not routeSuccess then
            pcall(conn.on_error, "Listener error for subPort " .. subPort .. ": " .. routeErr)
            conn:close()
        end
    end
    
    -- Start listening with error handling
    local listenSuccess, listenErr = tnet.listen(port, handleConnection)
    if not listenSuccess then
        return nil, "Failed to start multiplexer: " .. listenErr
    end
    listening = true
    
    -- Multiplexer object
    local mux = {
        port = port,
        listeners = listeners,
        connections = connections,
        listening = listening
    }
    
    -- Add listener method
    function mux:addListener(subPort, callback, wakeValidator)
        if listeners[subPort] then
            return false, "Listener already exists for subPort: " .. subPort
        end
        
        listeners[subPort] = {
            callback = callback,
            wakeValidator = wakeValidator
        }
        return true
    end
    
    -- Remove listener method
    function mux:removeListener(subPort)
        if not listeners[subPort] then
            return false, "No listener for subPort: " .. subPort
        end
        
        -- Close all connections for this sub-port
        for _, conn in pairs(connections) do
            if conn.subPort == subPort then
                conn:close()
            end
        end
        
        listeners[subPort] = nil
        return true
    end
    
    -- Close multiplexer method
    function mux:close()
        if not self.listening then return end
        
        tnet.stopListening(self.port)
        self.listening = false
        
        -- Close all connections
        for _, conn in pairs(self.connections) do
            conn:close()
        end
        self.connections = {}
        self.listeners = {}
    end
    
    -- Get active connections
    function mux:getConnections()
        return self.connections
    end
    
    -- Get listeners
    function mux:getListeners()
        return self.listeners
    end
    
    return mux
end

function tnet.stopListening(port)
    if listeners[port] then
        listeners[port] = nil
        return true
    end
    return false
end

function tnet.shutdown(quiet)
    if tnet.timeoutClock then
        event.cancel(tnet.timeoutClock)
        tnet.timeoutClock = nil
    end
    if tnet.routerEventID then
        event.ignore("modem_message", tnet.routerFunction)
        tnet.routerFunction = nil
        tnet.routerEventID = nil
    end
    
    -- Close all connections
    for id, conn in pairs(connections) do
        conn:close(quiet)
        connections[id] = nil
    end
    
    -- Stop all listeners
    for port in pairs(listeners) do
        tnet.stopListening(port)
    end
end

return tnet