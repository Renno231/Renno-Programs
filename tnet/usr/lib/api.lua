local api = {}
local tnet = require("tnet")
local computer = require("computer")
local table = table
-- Active exposed endpoints (servers)
api.endpoints = {}
-- Active client proxies
api.clients = {}
-- RPC Protocol Constants
local RPC_TYPE_CALL = "rpc_call"
local RPC_TYPE_RESPONSE = "rpc_response"
local RPC_TYPE_DOC_REQUEST = "rpc_doc_req"
local RPC_TYPE_DOC_RESPONSE = "rpc_doc_res"
local RPC_TYPE_PING = "rpc_ping"

-- SERVER SIDE
local Endpoint = {}
Endpoint.__index = Endpoint
function api.expose(name, target, port, keys)
    local lib = type(target) == "string" and require(target) or target
    
    if type(lib) ~= "table" then
        error("Target must be a table of functions or a require-able library name")
    end
    
    local endpoint = setmetatable({
        name = name,
        port = port,
        lib = lib,
        accessKey = nil,
        functionKeys = {},     -- fnName → required key
        functionDocs = {},     -- fnName → description
        connections = {},      -- address → connection object
        listening = false,     -- Track if endpoint is listening
        sDeny = true           -- do not send access denied
    }, Endpoint)
    
    for fnName, fnDef in pairs(lib) do
        if type(fnDef) == "function" then
            endpoint:exposeFunction(fnName, "Undocumented", keys and keys[fnName])
        elseif type(fnDef) == "table" and #fnDef >= 2 and type(fnDef[1]) == "function" and type(fnDef[2]) == "string" then
            endpoint:exposeFunction(fnName, fnDef[2], keys and keys[fnName])
            lib[fnName] = fnDef[1]
        end
    end
    
    local success, err = tnet.listen(port, function(conn)
        conn.serial = {lib = "serialization", encode = "serialize", decode = "unserialize"}
        
        if endpoint.accessKey and conn.wake ~= endpoint.accessKey then
            conn:close()
            return
        end
        endpoint.connections[conn.address] = conn
        
        local originalClose = conn.close
        conn.close = function(self, quiet)
            endpoint.connections[self.address] = nil
            originalClose(self, quiet)
        end
        
        conn:expect("rpc", function(c, _, msgType, ...)
            if msgType == RPC_TYPE_CALL then
                local fnName, callId, args, callKey = ...
                endpoint:handleCall(c, fnName, callId, args, callKey)
            elseif msgType == RPC_TYPE_DOC_REQUEST then
                local callId = ...
                endpoint:sendDoc(c, callId)
            elseif msgType == RPC_TYPE_PING then
                c:send("rpc", RPC_TYPE_PING, "pong")
            end
        end)
    end, function(wake)
        -- maybe there should be some distinction between the endpoint access key and the device key
        return not endpoint.accessKey or wake == endpoint.accessKey
    end)
    
    if not success then
        error("Failed to listen on port " .. port .. ": " .. err)
    end
    
    endpoint.listening = true
    api.endpoints[name] = endpoint
    
    return endpoint
end

function Endpoint:setAccessKey(key)
    self.accessKey = key
end

function Endpoint:setFunctionKeys(fnName, keys)
    if keys then
        if type(keys) == "table" then
            for i,k in pairs (keys) do
                if type(i) == "number" and type(k) == "string" then
                    keys[k]=true
                    keys[i]=nil
                end
            end
        else
            keys = {[tostring(keys)] = true}
        end
        self.functionKeys[fnName] = keys
    end
end

function Endpoint:exposeFunction(fnName, desc, keys)
    if not self.lib[fnName] then
        error("Function '" .. fnName .. "' not found in exposed library")
    end
    if type(self.lib[fnName]) ~= "function" then
        error("Exposed member '" .. fnName .. "' is not a function")
    end
    self.functionDocs[fnName] = desc or "No description"
    self:setFunctionKeys(fnName, keys)
end

function Endpoint:setSilentDeny(enabled)
    self.silentDeny = enabled
end

function Endpoint:handleCall(conn, fnName, callId, args, callKey)
    if not self.functionDocs[fnName] then
        if not self.silentDeny then
            conn:send("rpc", RPC_TYPE_RESPONSE, callId, false, "Function not exposed: " .. fnName)
        end
        return
    end
    
    local requiredKeys = self.functionKeys[fnName]
    if requiredKeys then
        if not callKey then
            conn:send("rpc", RPC_TYPE_RESPONSE, callId, false, "Missing function key for: " .. fnName)
            return
        end
        if not requiredKeys[callKey] then
            conn:send("rpc", RPC_TYPE_RESPONSE, callId, false, "Access denied to function: " .. fnName)
            return
        end
    end
    
    conn:send("rpc", RPC_TYPE_RESPONSE, callId, table.pack(pcall(self.lib[fnName], table.unpack(args or {}))))
end

function Endpoint:sendDoc(conn, callId)
    local doc = {}
    for fnName, desc in pairs(self.functionDocs) do
        doc[fnName] = {
            description = desc,
            requires_key = self.functionKeys[fnName] ~= nil
        }
    end
    conn:send("rpc", RPC_TYPE_DOC_RESPONSE, callId, doc)
end

function Endpoint:getConnections()
    return self.connections
end

function Endpoint:getConnection(clientAddress)
    return self.connections[clientAddress]
end

function Endpoint:shutdown()
    if not self.listening then return end
    
    tnet.stopListening(self.port)
    self.listening = false
    
    for address, conn in pairs(self.connections) do
        conn:close()
    end
    self.connections = {}
    
    api.endpoints[self.name] = nil
    return true
end

-- CLIENT SIDE
local RemoteProxy = {}
RemoteProxy.__index = RemoteProxy
function api.connect(endpointName, port, address, wakeKey, timeout, fnKeys)
    timeout = timeout or 5
    
    local conn = tnet.connect(address, port, wakeKey, "api_client")
    conn.serial = {lib = "serialization", encode = "serialize", decode = "unserialize"}
    
    local success, err = conn:init(timeout)
    if not success then
        error("Failed to connect to " .. address .. ":" .. port .. " - " .. (err or "timeout"))
    end
    
    local proxy = setmetatable({
        conn = conn,
        endpoint = endpointName,
        address = address,
        port = port,
        doc = nil,  -- lazy-loaded
        timeout = timeout,
        connected = true  -- Track connection state
    }, RemoteProxy)
    
    local clientKey = address .. ":" .. port .. "/" .. endpointName
    api.clients[clientKey] = proxy
    proxy:setFnKeyTable(fnKeys)
    return proxy
end

function RemoteProxy:listDocumentation()
    if not self.doc then
        self:refreshDocumentation()
    end
    return self.doc
end

function RemoteProxy:setFnKeyTable(newKeys) --functionName = key
    local oldKeys = self.keys
    if newKeys and type(newKeys) == "table" then
        self.keys = newKeys
    end
    return oldKeys
end

function RemoteProxy:refreshDocumentation()
    local callId = computer.uptime() .. "-" .. math.random(1000, 9999)
    local received = false
    local doc, err
    self.conn:expect(callId, function(_, result, error_msg)
        received = true
        if error_msg then
            err = error_msg
        else
            doc = result
        end
    end, 5)
    self.conn:send("rpc", RPC_TYPE_DOC_REQUEST, callId)
    local start = computer.uptime()
    while computer.uptime() - start < 5 and not received do
        os.sleep()
    end
    if not received then
        error("Timeout fetching documentation")
    end
    if err then
        error("Error fetching documentation: " .. err)
    end
    self.doc = doc
    return doc
end

-- Metamethod to allow remote.fn() syntax
function RemoteProxy:__index(key)
    -- First check if the key exists in the raw table
    local rawValue = rawget(self, key)
    if rawValue ~= nil then
        return rawValue
    end
    
    -- Then check if it's a method we own
    if RemoteProxy[key] then
        return RemoteProxy[key]
    end
    
    -- For remote functions, return a callable wrapper without checking documentation
    return function(...)
        local callKey = nil
        if self.keys and type(self.keys) == "table" then
            local keyVal = self.keys[key]
            if type(keyVal) == "string" then
                callKey = keyVal
            end
        end
        return self:callRemoteFunction(key, callKey, nil, ...)
    end
end

function RemoteProxy:async(callback)
    -- Return a temporary object to capture the function name via __index
    return setmetatable({}, {
        __index = function(_, fnName)
            -- Return the closure that actually executes the call
            return function(...)
                -- Resolve the access key (same logic as standard calls)
                local callKey = nil
                if self.keys and type(self.keys) == "table" then
                    local keyVal = self.keys[fnName]
                    if type(keyVal) == "string" then
                        callKey = keyVal
                    end
                end
                
                -- Execute internally with the callback
                return self:callRemoteFunctionInternal(fnName, callKey, callback, ...)
            end
        end
    })
end

function RemoteProxy:callRemoteFunction(fnName, callKey, asyncCallback, ...)
    if not self.connected then
        error("Connection is closed")
    end
    
    local callId = computer.uptime() .. "-" .. math.random(1000, 9999)
    local received, isAsync = false, type(asyncCallback) == "function"
    local result, err
    
    self.conn:expect("rpc", function(_, _, msgType, responseCallId, response, errorMsg)
        if msgType == RPC_TYPE_RESPONSE and responseCallId == callId then
            --print("DEBUG callRemoteFunction 8 - Matching response received")
            result = errorMsg and {false, errorMsg} or response
            if isAsync then
                if type(result) == "table" then
                    asyncCallback(table.unpack(result, 1, result.n))
                else
                    asyncCallback(result)
                end
            else
                received = true
            end
        end
    end, 10)
    
    local args = table.pack(...)
    self.conn:send("rpc", RPC_TYPE_CALL, fnName, callId, args, callKey)
    
    if isAsync then
        return true
    end

    local start = computer.uptime()
    local loopCount = 0
    while computer.uptime() - start < 10 and not received do
        loopCount = loopCount + 1
        os.sleep()
    end
    
    if not received then
        return false, ("Timeout calling remote function: " .. fnName)
    end
    
    if type(result) == "table" then
        return table.unpack(result, 1, result.n)
    else
        return result
    end
end

function RemoteProxy:getConnection()
    return self.conn
end

function RemoteProxy:close()
    if not self.connected then return end
    
    self.conn:close()
    self.connected = false
    
    -- Remove from global registry
    local clientKey = self.address .. ":" .. self.port .. "/" .. self.endpoint
    api.clients[clientKey] = nil
    return true
end

return api