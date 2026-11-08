-- The redraw loop. A loom GUI only needs drawing when something may have changed: after a signal
-- (touch, key, network message...), when a widget is animating, or when the program says so.
-- `run` waits for those instead of drawing continuously, so an idle GUI costs almost nothing.
local computer = require("computer")
local event = require("event")

local run = {}
local nextFrame = math.huge
local running = false

---Ask for a redraw within `delay` seconds (default: as soon as possible).
---Widgets call this while they animate; programs call it after changing widgets from a timer.
---@param delay? number
function run.request(delay)
    local t = computer.uptime() + (delay or 0)
    if t < nextFrame then nextFrame = t end
end

local onError
local logged = setmetatable({}, {__mode = "k"}) -- widget -> last error written to the log

---Set the function called when a widget's draw or an event handler errors:
---`handler(widget, message, during)`, where `during` is "draw" or the event name. Return true from
---a draw error to stop loom drawing its red error box over the widget. Returns the old handler.
---Without a handler, errors go to /tmp/loom.log (once per widget and message) and failed widgets
---show as a red box with the message.
---@param handler? function
---@return function?
function run.onError(handler)
    local old = onError
    onError = handler
    return old
end

---Report an error from `widget`. Returns true if a handler took care of it.
---@package
function run.error(widget, message, during)
    if onError then
        local ok, handled = pcall(onError, widget, message, during)
        if ok then return handled end
        message = message .. "\n(onError failed: " .. tostring(handled) .. ")"
    end
    if logged[widget] ~= message then
        logged[widget] = message
        local file = io.open("/tmp/loom.log", "a")
        if file then
            file:write(("[%.2f] %s error in %s\n%s\n"):format(computer.uptime(), during, tostring(widget.Class or "widget"), message))
            file:close()
        end
    end
end

---Run `f(...)`, reporting an error to `run.error` against `widget` instead of raising it.
---@package
function run.guard(widget, during, f, ...)
    local ok, err = xpcall(f, debug.traceback, ...)
    if not ok then run.error(widget, tostring(err), during) end
    return ok, err
end

---Make `run` return after the current event.
function run.stop() running = false end

---Draw `root`, then redraw it after every signal, whenever a widget asks for a frame, and at
---least every `interval` seconds (default 0.5). Returns after `stop()` is called.
---@param root Frame
---@param interval? number
function run.run(root, interval)
    interval = interval or 0.5
    running = true
    while running do
        nextFrame = math.huge
        root:draw()
        local now = computer.uptime()
        -- uptime moves in ticks (0.05 s) and a deadline exactly on a tick can land just after it
        -- in floating point, costing a whole extra tick; wake on the tick nearest the deadline
        event.pull(math.max(0, math.min(nextFrame, now + interval) - now - 0.025))
    end
end

return run
