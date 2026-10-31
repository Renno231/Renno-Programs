local tnet = {}
local connections = {}
local listeners = {}
local event = require("event")
local computer = require("computer")
local component = require("component")
local pack = table.pack

-- Serializers a peer may ask for. A peer names one of these; it never names a function.
tnet.serializers = {
    serialization = {encode = "serialize", decode = "unserialize"},
    cbor          = {encode = "encode",    decode = "decode"}
}

-- The network card with this address, or the primary card when none is named.
local function card(address)
    local primary = component.modem
    if not address or (primary and primary.address == address) then return primary end
    return component.proxy(address)
end

-- Packet type lookup table for shorter messages
local pTypeRev, pTypes = {}, {
    ['c'] = "connect",
    ['a'] = "connected", 
    ['d'] = "disconnect",
    ['s'] = "serialLib",
    ['m'] = "data"
}

-- Each boot starts at a random point, so an id seen again from the same peer is the same connection.
local nextId = math.random(0, 0xffff)
local function makeId()
    -- 4 chars from this computer
    local base, id = computer.address():sub(-8,-5)
    repeat
        id = base .. string.format("%04x", nextId % 0x10000)
        nextId = nextId + 1
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
        on_close     = nil,
        serial       = nil,
        connected    = fields.connected or false,
        msg_id       = 0,
        lastIn       = 0,   -- the peer's newest message id; one at or below it is a repeat
        frags        = {},  -- fragment buffers by message id
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
            for msg, cb in pairs(conn.expectations) do
                if cb.timeout and (now - cb.registered > cb.timeout) then
                    if conn.on_error then
                        pcall(conn.on_error, "Timeout waiting for response: " .. msg)
                    end
                    conn.expectations[msg] = nil
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

            for msg_id, frags in pairs(conn.frags) do
                if now - frags.last > 10 then
                    if conn.on_error then
                        pcall(conn.on_error, "Fragment buffer timeout (incomplete data)")
                    end
                    conn.frags[msg_id] = nil
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
        local listener = listeners[localPort]
        if packet_type == "connect" and listener and listener.modem.address == selfAddress then
            if listener.wakeValidator then
                local valid, result = pcall(listener.wakeValidator, wake)
                if not valid or not result then
                    return
                end
            end

            local ack_ninfo = table.concat({sys_name, conn_id, "0", pTypeRev["connected"]}, ",")
            local old = connections[conn_id]
            if old and old.address == senderAddress then
                -- The same connect heard again (a repeat or a resend), even after data: answer it again.
                pcall(old.modem.send, senderAddress, localPort, wake, ack_ninfo)
                return
            end
            if old then old:close(true) end  -- another peer took this id; the old connection ends

            local conn = newConnection({
                modem   = listener.modem,
                address = senderAddress,
                port    = localPort,
                wake    = wake,
                sys     = sys_name,
                id      = conn_id,
                connected = true,          -- because server side is already live
                wakeValidator = listener.wakeValidator
            })
            
            connections[conn_id] = conn
            pcall(conn.modem.send, senderAddress, localPort, wake, ack_ninfo)
            if listener.callback then
                pcall(listener.callback, conn)
            end
            return
        end
        
        local conn = connections[conn_id]
        if conn and conn.address == senderAddress and conn.sys == sys_name and conn.modem.address == selfAddress then
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
                local s = tnet.serializers[msg]
                if s then
                    conn.serial = {lib = msg, encode = s.encode, decode = s.decode}
                elseif conn.on_error then
                    pcall(conn.on_error, "Peer asked for an unknown serializer: " .. tostring(msg))
                end
            elseif packet_type == "data" then
                msg_id = tonumber(msg_id)
                if not msg_id or msg_id <= conn.lastIn then return end  -- a repeat
                if frag and maxFrag then
                    frag, maxFrag = tonumber(frag), tonumber(maxFrag)
                    local frags = conn.frags[msg_id] or {count = 0}
                    conn.frags[msg_id] = frags
                    frags.last = computer.uptime()
                    if not frags[frag] then
                        frags[frag] = args[1]
                        frags.count = frags.count + 1
                    end
                    if frags.count == maxFrag then
                        conn.frags[msg_id] = nil
                        conn.lastIn = msg_id
                        conn:handleMessage(msg, table.concat(frags))
                    end
                else
                    conn.lastIn = msg_id
                    conn:handleMessage(msg, table.unpack(args,1,args.n))
                end
            end
        else
        end
    end
    tnet.routerEventID = event.listen("modem_message", tnet.routerFunction)
end

function Connection:handleMessage(msg, ...)
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
    local cb_data = self.expectations[msg]
    if cb_data then
        -- Check timeout
        if cb_data.timeout and (computer.uptime() - cb_data.registered > cb_data.timeout) then
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

-- Called once when an open connection closes: by close(), a timeout or the peer's disconnect.
function Connection:onClose(callback)
    self.on_close = callback
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
    local wasConnected = self.connected
    if self.connected and not quiet then
        local ninfo = table.concat({self.sys, self.id, "0", pTypeRev["disconnect"]}, ",")
        pcall(self.modem.send, self.address, self.port, self.wake, ninfo)
    end
    self.default_callback = nil
    connections[self.id] = nil
    self.connected = false
    if wasConnected and self.on_close then
        pcall(self.on_close)
    end
end

-- lib names one of tnet.serializers; the peer is told to use it too.
function Connection:serialLib(lib)
    local s = assert(tnet.serializers[lib], "unknown serializer: " .. tostring(lib))
    self.serial = {lib = lib, encode = s.encode, decode = s.decode}
    if self.connected then
        local ninfo = table.concat({self.sys, self.id, "0", pTypeRev["serialLib"]}, ",")
        pcall(self.modem.send, self.address, self.port, self.wake, ninfo, lib)
    end
end

-- Public API
-- modem: the address of the card that reaches the peer; the primary card when omitted.
function tnet.connect(address, port, wake, sys, conn_id, wakeValidator, modem)
    modem = card(modem)
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

-- modem: the address of the only card that hears this port; the primary card when omitted.
function tnet.listen(port, callback, wakeValidator, modem)
    modem = card(modem)
    if not modem then
        return false, ("No modem component found")
    end
    
    if listeners[port] then
        return false, ("Already listening on port " .. port)
    end
    
    modem.open(port)

    listeners[port] = {
        callback = callback,
        wakeValidator = wakeValidator,
        modem = modem
    }
    
    if not tnet.routerEventID then 
        initRouter() 
    end
    if not tnet.timeoutClock then 
        startTimeoutChecker() 
    end
    
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
