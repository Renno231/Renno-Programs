local tnet = {}
local connections = {}
local listeners = {}
local uuid = require("uuid")
local event = require("event")
local computer = require("computer")
local component = require("component")

-- Packet type lookup table for shorter messages
local pTypeRev, pTypes = {}, {
    ['c'] = "connect",
    ['a'] = "connected", 
    ['d'] = "disconnect",
    ['s'] = "serialLib",
    ['m'] = "data"
}

for t, f in pairs (pTypes) do
    pTypeRev[f] = t
end
-- Connection object
local Connection = {}
Connection.__index = Connection

-- Timeout checker - only checks existing connections
local function startTimeoutChecker()
    if tnet.timeoutClock then return end
    tnet.timeoutClock = event.timer(1, function()
        local current_time = computer.uptime()
        for _, conn in pairs(connections) do
            -- Check connection-level timeout
            if conn.connection_timeout and conn.last_activity then
                if current_time - conn.last_activity > conn.connection_timeout then
                    if conn.on_error then
                        pcall(conn.on_error, "Connection timeout")
                    end
                    conn:close()
                end
            end

            -- Check message-specific timeouts
            for msg_id, cb in pairs(conn.expectations) do
                if cb.timeout and current_time - cb.registered > cb.timeout then
                    if conn.on_error then
                        pcall(conn.on_error, "Timeout waiting for response: " .. msg_id)
                    end
                    conn.expectations[msg_id] = nil
                end
            end

            -- Check default callback timeout
            if conn.default_callback and conn.default_callback.timeout then
                if current_time - conn.default_callback.registered > conn.default_callback.timeout then
                    if conn.on_error then
                        pcall(conn.on_error, "Default callback timeout")
                    end
                    conn.default_callback = nil
                end
            end
        end
    end, math.huge)
end

-- Router - fixed logic to properly handle connections and listeners
local function initRouter()
    if tnet.routerEventID then return end
    tnet.routerFunction = function(_, selfAddress, senderAddress, localPort, dist, wake, ninfo, msg, ...)
        wake, ninfo, msg = wake or "", ninfo or "", msg or ""
        -- Parse network information using split
        local ninfo_parts = {}
        for part in string.gmatch(ninfo, "[^,]+") do
            table.insert(ninfo_parts, part)
        end
        if #ninfo_parts < 4 then
            return
        end
        
        local sys_name, conn_id, msg_id, packet_type = table.unpack(ninfo_parts)
        
        -- Resolve packet type (support both short and long forms)
        packet_type = pTypes[packet_type] or packet_type
        local args = {...}
        
        -- Handle new connection requests to listeners
        if packet_type == "connect" and listeners[localPort] then
            local listener = listeners[localPort]
            
            -- Validate wake message if validator exists
            if listener.wakeValidator then
                local valid, result = pcall(listener.wakeValidator, wake)
                if not valid or not result then
                    return -- Reject connection
                end
            end
            
            -- Create new connection for this client
            local conn = setmetatable({
                modem = component.modem,
                address = senderAddress,
                port = localPort,
                wake = wake,
                sys = sys_name,
                id = conn_id,
                expectations = {},
                default_callback = nil,
                connection_timeout = nil,
                last_activity = computer.uptime(),
                on_error = nil,
                serial = nil,
                connected = true,
                msg_id = 0,
                wakeValidator = listener.wakeValidator
            }, Connection)
            
            connections[conn_id] = conn
            
            -- Send acknowledgment
            local ack_ninfo = table.concat({conn.sys or "server", conn.id, "0", pTypeRev["connected"]}, ",")
            pcall(conn.modem.send, senderAddress, localPort, wake, ack_ninfo)
            -- Notify listener
            if listener.callback then
                pcall(listener.callback, conn)
            end
            return
        end
        
        -- Handle messages for existing connections
        local conn = connections[conn_id]
        if conn and conn.address == senderAddress and conn.sys == sys_name then
            -- Validate wake message
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
                conn:handleMessage(msg_id, msg, table.unpack(args))
            end
        end
    end
    tnet.routerEventID = event.listen("modem_message", tnet.routerFunction)
end

function Connection:handleMessage(msg_id, msg, ...)
    self.last_activity = computer.uptime()
    local args = {...}

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
        local success, err = pcall(cb_data.callback, self, msg, table.unpack(args))
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
        local success, err = pcall(self.default_callback.callback, self, msg, table.unpack(args))
        if not success and self.on_error then
            pcall(self.on_error, "Default callback error: " .. tostring(err))
        end
    end
end

function Connection:expect(arg1, arg2, arg3, arg4)
    if type(arg1) == "function" then
        -- Default callback: expect(callback, timeout)
        self.default_callback = {
            callback = arg1,
            timeout = arg2,
            registered = computer.uptime()
        }
    else
        -- Specific callback: expect(msg_name, callback, timeout, persistent)
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
    local args = {...}

    -- Apply serialization
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
    local ninfo = table.concat({self.sys, self.id, self.msg_id, pTypeRev["data"]}, ",")
    local success = pcall(self.modem.send, self.address, self.port, self.wake, ninfo, msg, table.unpack(args))
    
    if not success then
        if self.on_error then
            pcall(self.on_error, "Send failed")
        end
        return nil
    end

    return self.msg_id
end

function Connection:init(timeout)
    timeout = timeout or 1
    local start_time = computer.uptime()
    
    -- Send connection request with proper packet type
    local ninfo = table.concat({self.sys, self.id, "0", pTypeRev["connect"]}, ",")
    
    pcall(self.modem.open, self.port)
    pcall(self.modem.send, self.address, self.port, self.wake, ninfo)
    
    -- Wait for connection acknowledgment
    while computer.uptime() - start_time < timeout do
        os.sleep()
        
        if self.connected then
            return true
        end
    end
    
    return false, "no response"
end

function Connection:close(quiet)
    if self.connected and not quiet then
        local ninfo = table.concat({self.sys, self.id, "0", pTypeRev["disconnect"]}, ",")
        pcall(self.modem.send, self.address, self.port, self.wake, ninfo)
    end
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
    
    local conn = setmetatable({
        modem = modem,
        address = address,
        port = port,
        wake = wake or computer.address(),
        sys = sys or "unknown",
        id = conn_id or uuid.next():sub(-12),
        expectations = {},
        default_callback = nil,
        connection_timeout = nil,
        last_activity = computer.uptime(),
        on_error = nil,
        serial = nil,
        connected = false,
        msg_id = 0,
        wakeValidator = wakeValidator
    }, Connection)

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
    
    -- Initialize router if needed
    if not tnet.routerEventID then initRouter() end
    if not tnet.timeoutClock then startTimeoutChecker() end
    
    return true
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