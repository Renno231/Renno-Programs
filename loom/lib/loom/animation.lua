-- Property animation ("tweening"). `widget:animate(to, seconds, options)` moves any of the widget's
-- numeric properties from their current values to `to` over time: position and size, colours
-- (blended per channel), or a widget's own values such as a ProgressBar's `value`. Each property
-- is set through the widget's own method, so callbacks and limits still apply.
-- Loaded on first use; widgets that never animate don't pay for it.
local computer = require("computer")
local run = require("loom.run")

local animation = {}

local function outBounce(t)
    if t < 1 / 2.75 then return 7.5625 * t * t
    elseif t < 2 / 2.75 then t = t - 1.5 / 2.75 return 7.5625 * t * t + 0.75
    elseif t < 2.5 / 2.75 then t = t - 2.25 / 2.75 return 7.5625 * t * t + 0.9375 end
    t = t - 2.625 / 2.75
    return 7.5625 * t * t + 0.984375
end

---Easing curves: progress (0..1) in, eased progress out. "in" starts slow, "out" ends slow.
animation.easing = {
    linear = function(t) return t end,
    inQuad = function(t) return t * t end,
    outQuad = function(t) return t * (2 - t) end,
    inOutQuad = function(t) return t < 0.5 and 2 * t * t or 1 - (2 - 2 * t) ^ 2 / 2 end,
    inCubic = function(t) return t * t * t end,
    outCubic = function(t) return 1 - (1 - t) ^ 3 end,
    inOutCubic = function(t) return t < 0.5 and 4 * t * t * t or 1 - (2 - 2 * t) ^ 3 / 2 end,
    outBack = function(t) return 1 + 2.70158 * (t - 1) ^ 3 + 1.70158 * (t - 1) ^ 2 end, -- overshoots, settles back
    outElastic = function(t)
        if t == 0 or t == 1 then return t end
        return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
    end,
    outBounce = outBounce,
    inBounce = function(t) return 1 - outBounce(1 - t) end,
}

-- Properties set in whole cells.
local whole = {x = true, y = true, width = true, height = true}

local function blend(a, b, k)
    local function channel(shift)
        local ca, cb = (a >> shift) & 0xff, (b >> shift) & 0xff
        return math.max(0, math.min(255, math.floor(ca + (cb - ca) * k + 0.5))) << shift
    end
    return channel(16) | channel(8) | channel(0)
end

---A running animation. Fields: `widget`, `to`, `done`.
---@class Animation
local Animation = {}
Animation.__index = Animation

---Stop where it is. `onDone` is not called.
function Animation:cancel()
    self.done = true
end

---Jump to the end (of the last repeat) and finish now.
function Animation:finish()
    if self.done then return end
    self.repeats, self.started = 0, -math.huge
    self.delay, self.reverse = 0, self.yoyo and self.reverse
    animation.step(self.widget)
end

local function apply(a, k)
    local widget, from = a.widget, a.from
    for name, to in pairs(a.to) do
        local start = from[name]
        if start == nil then start = to end -- unset (a colour, say): jump to the target
        local value
        if a.color[name] then
            value = blend(start, to, k)
        else
            value = start + (to - start) * k
            if whole[name] then value = math.floor(value + 0.5) end
        end
        widget[name](widget, value)
    end
end

---Start animating `widget` towards `to` (property name -> target value) over `seconds`.
---Options: `easing` (a name from animation.easing or a function, default "linear"), `delay`
---(seconds), `repeats` (extra runs, `true` = forever), `yoyo` (every other run goes back),
---`onDone(widget, animation)`. When it ends the widget also gets an "animationDone" event.
---A property being animated already moves to the new animation.
---@return Animation
function animation.start(widget, to, seconds, options)
    options = options or {}
    local easing = options.easing or "linear"
    if type(easing) == "string" then
        easing = animation.easing[easing] or error("unknown easing '" .. easing .. "'", 3)
    end
    local repeats = options.repeats
    local targets = {}
    for name, value in pairs(to) do targets[name] = value end
    local a = setmetatable({
        widget = widget, to = targets, color = {}, seconds = seconds or 0.5, easing = easing,
        delay = options.delay or 0, started = computer.uptime(),
        repeats = repeats == true and math.huge or repeats or 0, yoyo = options.yoyo, onDone = options.onDone,
    }, Animation)
    for name in pairs(targets) do
        if type(widget[name]) ~= "function" then error("widget has no property '" .. tostring(name) .. "'", 3) end
        if name:find("Color$") then a.color[name] = true end
    end
    local list = widget._anims
    if not list then list = {} widget._anims = list end
    for _, other in ipairs(list) do -- take over properties already animating
        local left = false
        for name in pairs(targets) do other.to[name] = nil end
        for _ in pairs(other.to) do left = true break end
        if not left then other.done = true end
    end
    list[#list + 1] = a
    run.request(0)
    return a
end

---Advance `widget`'s animations; called by its frame before drawing it.
function animation.step(widget)
    local list = widget._anims
    if not list then return end
    local now = computer.uptime()
    local n, count = 0, #list
    for i = 1, count do
        local a = list[i]
        if not a.done then
            local elapsed = now - a.started - a.delay
            if elapsed < 0 then
                run.request(-elapsed)
            else
                if not a.from then -- start from wherever the widget is when the delay ends
                    a.from = {}
                    for name in pairs(a.to) do a.from[name] = widget[name](widget) end
                end
                local t = a.seconds > 0 and math.min(1, elapsed / a.seconds) or 1
                local k = a.easing(t)
                apply(a, a.reverse and 1 - k or k)
                if t < 1 then
                    run.request(0.05)
                elseif a.repeats > 0 then
                    a.repeats, a.started, a.delay = a.repeats - 1, now, 0
                    if a.yoyo then a.reverse = not a.reverse end
                    run.request(0.05)
                else
                    a.done = true
                    if a.onDone then run.guard(widget, "animationDone", a.onDone, widget, a) end
                    widget:invokeCallback("animationDone", a)
                end
            end
        end
        if not a.done then n = n + 1 list[n] = a end
    end
    local total = #list -- onDone may have started more
    for i = count + 1, total do n = n + 1 list[n] = list[i] end
    for i = n + 1, total do list[i] = nil end
    if n == 0 and widget._anims == list then widget._anims = nil end
end

---Targets of the running animation of property `name`, or nil.
function animation.target(widget, name)
    for _, a in ipairs(widget._anims or {}) do
        if not a.done and a.to[name] ~= nil then return a.to[name] end
    end
end

return animation
