local tnet = {}
local connections = {}
local listeners = {}
local event = require("event")
local computer = require("computer")
local component = require("component")
local pack = table.pack
local stopIfIdle -- below the router

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

-- Sends as modem.send, checking for a local peer first: OC never hands a card a message sent
-- to its own address, so one to this card, on a port open on it, is pushed as the
-- modem_message signal the card would raise. Programs on one computer reach each other so.
local function send(modem, address, port, ...)
    if address ~= modem.address then return modem.send(address, port, ...) end
    if modem.isOpen(port) then computer.pushSignal("modem_message", address, address, port, 0, ...) end
    return true
end
-- Both ends of a local connection share one table here and the id it was made with: the
-- accepting end is kept under that id with "<" added. A local packet carries its sender's id,
-- so it is for the other end.
local function otherEnd(id) return id:sub(-1) == "<" and id:sub(1, -2) or id .. "<" end

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

-- The router and the timeout clock run while tnet holds a connection or a listener; the next
-- connect or listen starts them again.
local function stopRouter()
    if tnet.timeoutClock then
        event.cancel(tnet.timeoutClock)
        tnet.timeoutClock = nil
    end
    if tnet.routerEventID then
        event.ignore("modem_message", tnet.routerFunction)
        tnet.routerFunction = nil
        tnet.routerEventID = nil
    end
end
stopIfIdle = function()
    if not next(connections) and not next(listeners) then stopRouter() end
end

local function initRouter()
    if tnet.routerEventID then return end
    tnet.routerFunction = function(_, selfAddress, senderAddress, localPort, dist, wake, ninfo, msg, ...)
        wake, ninfo, msg = wake or "", ninfo or "", msg or ""
        -- Another program's message on a tnet port (GNS link calls share the gate's port).
        if type(ninfo) ~= "string" then return end
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
        local here = senderAddress == selfAddress -- a local peer (send, above)
        if packet_type == "connect" and listener and listener.modem.address == selfAddress then
            if listener.wakeValidator then
                local valid, result = pcall(listener.wakeValidator, wake)
                if not valid or not result then
                    return
                end
            end

            local id = here and otherEnd(conn_id) or conn_id
            local ack_ninfo = table.concat({sys_name, id, "0", pTypeRev["connected"]}, ",")
            local old = connections[id]
            if old and old.address == senderAddress then
                -- The same connect heard again (a repeat or a resend), even after data: answer it again.
                pcall(send, old.modem, senderAddress, localPort, wake, ack_ninfo)
                return
            end
            if old then old:close(true) end  -- another peer took this id; the old connection ends

            local conn = newConnection({
                modem   = listener.modem,
                address = senderAddress,
                port    = localPort,
                wake    = wake,
                sys     = sys_name,
                id      = id,
                connected = true,          -- because server side is already live
                wakeValidator = listener.wakeValidator
            })
            
            connections[id] = conn
            if listener.bucket then listener.bucket:add(conn) end
            pcall(send, conn.modem, senderAddress, localPort, wake, ack_ninfo)
            if listener.callback then
                pcall(listener.callback, conn)
            end
            return
        end
        
        local conn = connections[here and otherEnd(conn_id) or conn_id]
        if conn and conn.address == senderAddress and conn.sys == sys_name and conn.modem.address == selfAddress then
            if conn.wakeValidator then
                local valid, result = pcall(conn.wakeValidator, wake)
                if not valid or not result then
                    return
                end
            end
            
            if packet_type == "connected" then
                if not conn.connected then
                    conn.connected = true
                    if conn.on_open then pcall(conn.on_open) end
                end
                local ready = conn.on_ready
                conn.on_ready = nil
                if ready then ready(true) end
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

-- Called once when the peer answers the connection request.
function Connection:onOpen(callback)
    self.on_open = callback
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
                success, failed = pcall(send, self.modem, self.address, self.port, self.wake,
                                        ninfo..","..tostring(cFrag)..","..tostring(totalFrags), msg, args[1]:sub((cFrag-1) * dataMax + 1, cFrag * dataMax))
                if not success then break end
            end
        end
    end
    if single then
        success, failed = pcall(send, self.modem, self.address, self.port, self.wake, ninfo, msg, table.unpack(args,1,args.n))
    end
    if not success then
        if self.on_error then
            pcall(self.on_error, "Send failed" .. failed)
        end
        return nil
    end
    return self.msg_id
end 

-- Sends the connection request, or sends it again: the peer answers a repeat on the
-- same connection, and the wake key powers it on if it is off.
function Connection:request()
    local ninfo = table.concat({self.sys, self.id, "0", pTypeRev["connect"]}, ",")
    pcall(self.modem.open, self.port)
    pcall(send, self.modem, self.address, self.port, self.wake, ninfo)
end

-- Asks the peer to accept the connection. Without a callback, waits up to timeout seconds and
-- returns true, or false and "no response". With one, returns at once and later calls
-- callback(true), or callback(false, "no response") after timeout. A connection closed before
-- then calls neither.
function Connection:init(timeout, callback)
    timeout = timeout or 1
    local start_time = computer.uptime()

    if callback then
        self.ready_timer = event.timer(timeout, function()
            self.ready_timer = nil
            if self.on_ready then
                self.on_ready = nil
                callback(false, "no response")
            end
        end)
        self.on_ready = function()
            if self.ready_timer then event.cancel(self.ready_timer) self.ready_timer = nil end
            callback(true)
        end
    end
    self:request()
    if callback then return end

    while computer.uptime() - start_time < timeout do
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
        pcall(send, self.modem, self.address, self.port, self.wake, ninfo)
    end
    self.default_callback = nil
    self.on_ready = nil
    if self.ready_timer then event.cancel(self.ready_timer) self.ready_timer = nil end
    if connections[self.id] == self then connections[self.id] = nil end
    self.connected = false
    if self.bucket then self.bucket:remove(self) end
    if wasConnected and self.on_close then
        pcall(self.on_close)
    end
    stopIfIdle()
end

-- lib names one of tnet.serializers; the peer is told to use it too.
function Connection:serialLib(lib)
    local s = assert(tnet.serializers[lib], "unknown serializer: " .. tostring(lib))
    self.serial = {lib = lib, encode = s.encode, decode = s.decode}
    if self.connected then
        local ninfo = table.concat({self.sys, self.id, "0", pTypeRev["serialLib"]}, ",")
        pcall(send, self.modem, self.address, self.port, self.wake, ninfo, lib)
    end
end

-- Buckets. A bucket holds what one program made through tnet (and api): its connections, its
-- listeners, the connections those listeners accepted, and anything else with a close method.
-- Closing it closes those and nothing of any other program's; tnet.shutdown closes everything.
-- A bucket closes by itself when the program that made it ends, crashed or not. A service that
-- outlives the command that started it detaches its bucket and closes it when it stops.
local Bucket = {}
Bucket.__index = Bucket
local buckets = {}

function tnet.bucket(name)
    local bucket = setmetatable({name = name, members = {}}, Bucket)
    buckets[bucket] = true
    local ok, process = pcall(require, "process")
    local proc = ok and process.info()
    if proc then
        bucket.process = proc
        process.addHandle(bucket, proc)
    end
    return bucket
end

-- Keeps member (anything with close(self, quiet)) in the bucket until it or the bucket closes.
function Bucket:add(member)
    assert(buckets[self], "bucket is closed")
    self.members[member] = true
    member.bucket = self
    return member
end

-- For a member that closed by itself.
function Bucket:remove(member)
    self.members[member] = nil
    if rawget(member, "bucket") == self then member.bucket = nil end
end

-- The bucket stays open when the program that made it ends.
function Bucket:detach()
    if self.process then
        require("process").removeHandle(self, self.process)
        rawset(self, "close", nil) -- process.addHandle's wrapper
        self.process = nil
    end
    return self
end

function Bucket:close(quiet)
    if not buckets[self] then return end
    buckets[self] = nil
    for member in pairs(self.members) do
        self.members[member] = nil
        member.bucket = nil
        pcall(member.close, member, quiet)
    end
end

function Bucket:connect(address, port, wake, sys, conn_id, wakeValidator, modem)
    assert(buckets[self], "bucket is closed")
    return self:add(tnet.connect(address, port, wake, sys, conn_id, wakeValidator, modem))
end

function Bucket:listen(port, callback, wakeValidator, modem)
    assert(buckets[self], "bucket is closed")
    local ok, err = tnet.listen(port, callback, wakeValidator, modem)
    if not ok then return ok, err end
    self:add(listeners[port])
    return true
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

-- A listener closes as tnet.stopListening(port) does.
local Listener = {}
Listener.__index = Listener
function Listener:close()
    if listeners[self.port] == self then tnet.stopListening(self.port) end
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

    listeners[port] = setmetatable({
        port = port,
        callback = callback,
        wakeValidator = wakeValidator,
        modem = modem
    }, Listener)

    if not tnet.routerEventID then
        initRouter()
    end
    if not tnet.timeoutClock then
        startTimeoutChecker()
    end

    return true
end

function tnet.stopListening(port)
    local listener = listeners[port]
    if not listener then return false end
    listeners[port] = nil
    if listener.bucket then listener.bucket:remove(listener) end
    stopIfIdle()
    return true
end

-- Closes every bucket, connection and listener on this computer.
function tnet.shutdown(quiet)
    for bucket in pairs(buckets) do bucket:close(quiet) end
    for id, conn in pairs(connections) do
        conn:close(quiet)
        connections[id] = nil
    end
    for port in pairs(listeners) do
        tnet.stopListening(port)
    end
    stopRouter()
end

return tnet
