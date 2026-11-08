-- Keyboard focus and navigation. One widget at a time has focus; focusable widgets (buttons,
-- switches, sliders, lists, dropdowns, text fields, or any widget marked `focusable(true)`) are
-- collected as they are drawn, so only what is on screen can take focus.
--
-- Keys go to the focused widget first (`_key`); what it doesn't use:
--   Tab / Shift+Tab   next / previous widget in reading order
--   arrows            the nearest widget in that direction
--   Enter / Space     a touch on the widget, so touch callbacks work unchanged
--   anything else     the `onKey` handler, if set (screen shortcuts, quit keys)
-- While `loom.run` runs, keys are always listened for; otherwise only while a widget has focus.
-- A touch on a focusable widget focuses it; a touch elsewhere clears focus.
local event = require("event")
local keyboard = require("keyboard")
local gpu = require("loom.gpu")
local run = require("loom.run")

local input = {}
local focused, listeners, attached, keyHandler
local frameOf = setmetatable({}, {__mode = "k"}) -- widget -> last frame it was drawn in
local orderOf = setmetatable({}, {__mode = "k"}) -- widget -> drawing order in that frame
local counter, counterFrame = 0, nil

local TAB, ESCAPE, ENTER, KEYPAD_ENTER, SPACE = 15, 1, 28, 156, 57
local MOVES = {[200] = {0, -1}, [208] = {0, 1}, [203] = {-1, 0}, [205] = {1, 0}}
local hookOwner = {Class = "onKey"} -- errors in the key handler are reported against this

---Note that `widget` was drawn this frame and can take focus.
function input.shown(widget)
    local frame = gpu.frames
    if frameOf[widget] == frame then return end
    if counterFrame ~= frame then counterFrame, counter = frame, 0 end
    counter = counter + 1
    frameOf[widget], orderOf[widget] = frame, counter
end

---Forget a widget that is being destroyed.
function input.forget(widget)
    if focused == widget then input.focus(nil) end
    frameOf[widget], orderOf[widget] = nil, nil
end

---The focused widget, or nil.
function input.focused() return focused end

-- A widget can take keys if it and every frame it sits in are enabled.
local function enabled(w)
    while w do
        if not w:enabled() then return false end
        w = w:getParent()
    end
    return true
end

-- Focusable widgets drawn in the latest frame.
local function onScreen()
    local list, frame = {}, gpu.frames
    for w, f in pairs(frameOf) do
        if f == frame and enabled(w) then list[#list + 1] = w end
    end
    return list
end

local function byPosition(a, b)
    local ay, by = a:absY(), b:absY()
    if ay ~= by then return ay < by end
    return a:absX() < b:absX()
end

---Move focus to the next (or previous) widget in reading order.
function input.next(back)
    local list = onScreen()
    if #list == 0 then return end
    table.sort(list, byPosition)
    local at = 0
    for i, w in ipairs(list) do if w == focused then at = i break end end
    local player = focused and focused._player
    if at == 0 then at = back and #list or 1 else at = (at + (back and -2 or 0)) % #list + 1 end
    input.focus(list[at], player)
end

---Move focus to the nearest widget in direction dx, dy (one of them 0, the other 1 or -1).
---Distance is measured between centres, along the direction plus three times across it, with rows
---counted double since cells are twice as tall as they are wide. Returns true if focus moved.
function input.move(dx, dy)
    if not focused then input.next(false) return focused ~= nil end
    local fx, fy = focused:absX() + focused:width() / 2, focused:absY() + focused:height() / 2
    local best, bestScore
    for _, w in ipairs(onScreen()) do
        if w ~= focused then
            local ox, oy = w:absX() + w:width() / 2 - fx, (w:absY() + w:height() / 2 - fy) * 2
            local along, across = ox * dx + oy * dy, math.abs(ox * dy - oy * dx)
            if along > 0 then
                local score = along + across * 3
                if not bestScore or score < bestScore then best, bestScore = w, score end
            end
        end
    end
    if best then input.focus(best, focused._player) return true end
    return false
end

---Do what a touch on `widget` does (at its top-left cell).
function input.activate(widget, player)
    return widget:invokeCallback("touch", gpu.getScreen(), widget:absX(), widget:absY(), 0, player)
end

---Set the handler for keys no widget used: `handler(char, code, player)`. Returns the old one.
---@param handler? function
---@return function?
function input.onKey(handler)
    local old = keyHandler
    keyHandler = handler
    return old
end

local function onKey(_, _, char, code, player)
    local w = focused
    if w and (frameOf[w] and frameOf[w] ~= gpu.frames or not enabled(w)) then -- drawn before, not now
        input.focus(nil)
        w = nil
    end
    if w and w._player and player and w._player ~= player then return end
    if code == TAB then input.next(keyboard.isShiftDown()) return end
    if w then
        local ok, used = run.guard(w, "key_down", w._key, w, char, code, keyboard.isControlDown(), player)
        if ok and used then run.request(0) return end
        if code == ENTER or code == KEYPAD_ENTER or code == SPACE then
            run.guard(w, "touch", input.activate, w, player)
            run.request(0)
            return
        end
    end
    local move = MOVES[code]
    if move and input.move(move[1], move[2]) then return end
    if keyHandler then
        run.guard(hookOwner, "key_down", keyHandler, char, code, player)
        run.request(0)
    elseif code == ESCAPE and w then
        input.focus(nil)
    end
end

local function onPaste(_, _, text, player)
    local w = focused
    if w and w._paste and enabled(w) and not (w._player and player and w._player ~= player) then
        run.guard(w, "clipboard", w._paste, w, text)
    end
end

local function onTouch(_, _, x, y)
    local hit, best
    for _, w in ipairs(onScreen()) do
        if w:checkCollision(x, y) and (not best or orderOf[w] > best) then hit, best = w, orderOf[w] end
    end
    if hit then input.focus(hit, focused == hit and focused._player or nil)
    elseif focused then input.focus(nil) end
end

local function listen()
    if not listeners then
        listeners = {event.listen("key_down", onKey), event.listen("clipboard", onPaste), event.listen("touch", onTouch)}
    end
end

local function unlisten()
    if listeners and not attached and not focused then
        for _, id in ipairs(listeners) do event.cancel(id) end
        listeners = nil
    end
end

---Listen for keys until `detach` (loom.run does this while it runs).
function input.attach() attached = true listen() end

---Stop listening and clear focus.
function input.detach()
    attached = false
    input.focus(nil)
    unlisten()
end

---Give `widget` focus (nil clears it). `player`, if given, is the only player whose keys count.
---@param widget? Widget
---@param player? string
function input.focus(widget, player)
    local old = focused
    if widget == old then
        if widget then widget._player = player end
        return
    end
    focused = widget
    if old then
        old._player = nil
        if old.invokeCallback then old:invokeCallback("blur") end
    end
    if widget then
        widget._player = player
        widget:invokeCallback("focus")
        listen()
    else
        unlisten()
    end
    run.request(0)
end

return input
