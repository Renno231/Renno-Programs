-- The redraw loop. A loom GUI only needs drawing when something may have changed: after a signal
-- (touch, key, network message...), when a widget is animating, or when the program says so.
-- `run` waits for those instead of drawing continuously, so an idle GUI costs almost nothing.
local computer = require("computer")
local event = require("event")
local gpu = require("loom.gpu")

local run = {}
local nextFrame = math.huge
local parts = {} -- widget -> when it wants its part redrawn
local running = false

---Ask for a redraw within `delay` seconds (default: as soon as possible).
---Widgets call this while they animate; programs call it after changing widgets from a timer.
---A widget that draws its own part of the frame (see `gpu.part`) passes itself: if nothing else
---needs drawing by then, only its part is redrawn.
---@param delay? number
---@param widget? Widget
function run.request(delay, widget)
    local t = computer.uptime() + (delay or 0)
    if widget then
        if t < (parts[widget] or math.huge) then parts[widget] = t end
    elseif t < nextFrame then nextFrame = t end
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
---least every `interval` seconds (default 0.5). A widget that asked for its part alone, with
---nothing else due, has only its part redrawn. Returns after `stop()` is called.
---@param root Frame
---@param interval? number
function run.run(root, interval)
    interval = interval or 0.5
    local input = require("loom.input")
    input.attach() -- keys are listened for the whole time, for keyboard navigation
    running = true
    -- uptime moves in ticks (0.05 s) and a deadline exactly on a tick can land just after it in
    -- floating point, costing a whole extra tick; wake on the tick nearest the deadline, and count
    -- what is due by then as due
    local HALF_TICK = 0.025
    local ok, err = pcall(function()
        local whole, lastWhole, due = true, 0, {}
        while running do
            local now = computer.uptime()
            if whole then
                nextFrame, lastWhole = math.huge, now
                for widget in pairs(parts) do parts[widget] = nil end -- drawn widgets ask again
                root:draw()
                if not next(parts) then gpu.release() end -- nothing animates alone
            else
                local count = 0
                for widget, t in pairs(parts) do
                    if t <= now + HALF_TICK then count = count + 1 due[count] = widget parts[widget] = nil end
                end
                for i = count + 1, #due do due[i] = nil end
                if count > 0 then root:_redraw(due) end
            end
            now = computer.uptime()
            local wake = math.min(nextFrame, lastWhole + interval)
            for _, t in pairs(parts) do if t < wake then wake = t end end
            local signal = event.pull(math.max(0, wake - now - HALF_TICK))
            now = computer.uptime() + HALF_TICK
            whole = signal ~= nil or nextFrame <= now or lastWhole + interval <= now
        end
    end)
    input.detach()
    if not ok then error(err, 0) end
end

return run
