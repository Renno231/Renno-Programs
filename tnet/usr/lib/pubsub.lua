-- Exact-topic events on tnet connections, independent of API's RPC dispatcher.
local pubsub = {}
local states = setmetatable({}, {__mode = "k"})

local function topicName(topic)
    assert(type(topic) == "string" and topic ~= "", "Topic must be a nonempty string")
    return topic
end

local function stateFor(conn)
    local state = states[conn]
    if state then return state end
    state = {topics = {}, callbacks = {}, serving = false}
    states[conn] = state
    conn:expect("ps", function(_, _, kind, topic, ...)
        if type(topic) ~= "string" or topic == "" then return end
        if kind == "sub" and state.serving then
            state.topics[topic] = true
        elseif kind == "unsub" and state.serving then
            state.topics[topic] = nil
        elseif kind == "event" then
            local callback = state.callbacks[topic]
            if callback then callback(...) end
        end
    end, nil, true)
    return state
end

local Publisher = {}
Publisher.__index = Publisher

local function publisher()
    return setmetatable({connections = {}}, Publisher)
end

function Publisher:publish(topic, ...)
    topicName(topic)
    local sent = 0
    for conn, state in pairs(self.connections) do
        if not conn.connected then
            state.topics = {}
            self.connections[conn] = nil
        elseif state.topics[topic] then
            if conn:send("ps", "event", topic, ...) then sent = sent + 1 end
        end
    end
    return sent
end

local function attachConnection(pub, conn)
    local state = stateFor(conn)
    state.serving = true
    pub.connections[conn] = state
end

function pubsub.server(conn)
    local pub = publisher()
    attachConnection(pub, conn)
    return pub
end

function pubsub.attach(endpoint)
    local pub = publisher()
    endpoint:onConnect(function(conn) attachConnection(pub, conn) end)
    for _, conn in pairs(endpoint:getConnections()) do
        attachConnection(pub, conn)
    end
    return pub
end

function pubsub.client(conn)
    local state = stateFor(conn)
    local sub = {}
    function sub:subscribe(topic, callback)
        topicName(topic)
        assert(type(callback) == "function", "Subscription callback must be a function")
        local previous = state.callbacks[topic]
        state.callbacks[topic] = callback
        local result = conn:send("ps", "sub", topic)
        if not result then state.callbacks[topic] = previous end
        return result
    end
    function sub:unsubscribe(topic)
        topicName(topic)
        state.callbacks[topic] = nil
        return conn:send("ps", "unsub", topic)
    end
    return sub
end

return pubsub
