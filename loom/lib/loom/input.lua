-- Keyboard focus. One widget at a time owns the keyboard. Focusing it starts listening for keys,
-- pastes and touches; clearing focus stops. Tab and Shift+Tab move between the focusable widgets
-- drawn in the latest frame, in reading order. Escape and a touch elsewhere clear focus.
local event = require("event")
local keyboard = require("keyboard")
local gpu = require("loom.gpu")
local run = require("loom.run")

local input = {}
local focused, listeners
local shown = setmetatable({}, {__mode = "k"}) -- widget -> last frame it was drawn in

---Note that `widget` was drawn this frame and can take focus with Tab.
function input.shown(widget) shown[widget] = gpu.frames end

---Forget a widget that is being destroyed: release the keyboard and drop it from the Tab order.
function input.forget(widget)
    if focused == widget then input.focus(nil) end
    shown[widget] = nil
end

---The widget that owns the keyboard, or nil.
function input.focused() return focused end

local function byPosition(a, b)
    local ay, by = a:absY(), b:absY()
    if ay ~= by then return ay < by end
    return a:absX() < b:absX()
end

---Move focus to the next (or previous) focusable widget on screen.
function input.next(back)
    local list = {}
    for w, frame in pairs(shown) do
        if frame == gpu.frames and w:enabled() then list[#list + 1] = w end
    end
    if #list == 0 then return end
    table.sort(list, byPosition)
    local at = 0
    for i, w in ipairs(list) do if w == focused then at = i break end end
    local player = focused and focused._player
    if at == 0 then at = back and #list or 1 else at = (at + (back and -2 or 0)) % #list + 1 end
    input.focus(list[at], player)
end

local function onKey(_, _, char, code, player)
    local w = focused
    if not w or (w._player and player and w._player ~= player) then return end
    if code == 15 then -- Tab
        input.next(keyboard.isShiftDown())
    elseif code == 1 then -- Escape
        input.focus(nil)
    elseif w:enabled() then
        run.guard(w, "key_down", w._key, w, char, code, keyboard.isControlDown())
    end
end

local function onPaste(_, _, text, player)
    local w = focused
    if w and w:enabled() and not (w._player and player and w._player ~= player) then run.guard(w, "clipboard", w._paste, w, text) end
end

local function onTouch(_, _, x, y)
    if focused and not focused:checkCollision(x, y) then input.focus(nil) end
end

---Give `widget` the keyboard (nil clears focus). `player`, if given, is the only player whose keys count.
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
        old:invokeCallback("blur")
    end
    if widget then
        widget._player = player
        widget:invokeCallback("focus")
        if not listeners then
            listeners = {event.listen("key_down", onKey), event.listen("clipboard", onPaste), event.listen("touch", onTouch)}
        end
    elseif listeners then
        for _, id in ipairs(listeners) do event.cancel(id) end
        listeners = nil
    end
    run.request(0)
end

return input
