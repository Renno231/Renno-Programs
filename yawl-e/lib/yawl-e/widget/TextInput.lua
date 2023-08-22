local event = require("event")
local wrap = require("yawl-e.util").wrap
local class = require("libClass2")
local Text = require("yawl-e.widget.Text")
local gpu = require("component").gpu

--[[
    TODO
        cursor
            should it be a full space blink that inverts the color of the character it overlaps?
            should it be a | or similar character that it flips between with the character it overlaps?
        
        add listener for paste event
]]

---@class TextInput:Text
---@field private _listeners.keyDownEvent number
---@field private _listeners.touchEvent number
---@field private _placeHolderChar string
---@operator call:TextInput
---@overload fun(parent:Frame,x:number,y:number,text:string,foregroundColor:number):TextInput
local TextInput = class(Text)

---@param value? string
---@return string
function TextInput:placeholder(value)
    checkArg(1, value, 'string', 'nil')
    local oldValue = self._placeholder
    if (value) then self._placeholder = value end
    return oldValue
end

function TextInput:_onKeyDown(eventName, component, char, key, player)
    if (eventName ~= "key_down") then return end
    if (char == 8) then                                --backspace
        self:text(string.sub(self:text(), 0, -2))
    elseif (char == 13 and not self:multilines()) then --return
        event.cancel(self._listeners.keyDownEvent)
        self._listeners.keyDownEvent = nil
        event.cancel(self._listeners.touchEvent)
        self._listeners.touchEvent = nil
    elseif (char ~= 0) then
        self:text(self:text() .. string.char(char))
    end
end

function TextInput:clearOnEnter(should)
    checkArg(1, should, 'boolean', 'nil')
    local oldValue = self._clearOnEnter or false
    if (should ~= nil) then self._clearOnEnter = should end
    return oldValue
end

function TextInput:callback(callback, ...)
    checkArg(1, callback, 'nil')
    return TextInput.defaultCallback
end

function TextInput:defaultCallback(_, eventName, uuid, x, y, button, playerName)
    if (eventName ~= "touch") then return end
    if button ~= 0 then self:text("") end
    if button == 0 and (not self._listeners.keyDownEvent) then
        self._listeners.keyDownEvent = event.listen("key_down", function(...) self:_onKeyDown(...) end) --[[@as number]]
        self._listeners.touchEvent = event.listen("touch", function(eventName, uuid, x, y, button, playerName)
            if (not self:checkCollision(x, y)) then
                if (self._listeners.keyDownEvent) then event.cancel(self._listeners.keyDownEvent --[[@as number]]) end
                self._listeners.keyDownEvent = nil
                if (self._listeners.touchEvent) then event.cancel(self._listeners.touchEvent --[[@as number]]) end
                self._listeners.touchEvent = nil
                if self:clearOnEnter() then self:text("") end
            end
        end) --[[@as number]]
    end
end

---@param value? boolean
---@return boolean
function TextInput:multilines(value)
    checkArg(1, value, 'boolean', 'nil')
    local oldValue = self._multilines or false
    if (value ~= nil) then self._multilines = value end
    return oldValue
end

function TextInput:cursor(x,y) --if x and y, x specifies the char on the line y points to, if just x, it's the char at the index in the normal string
    checkArg(1, x, 'number', 'nil')
    checkArg(1, y, 'number', 'nil')
    
end

function TextInput:cursorChar(char)

end

function TextInput:append(str) --inserts at the current cursor position

end

function TextInput:backspace(num) --how many characters to the left or right of the cursor to delete

end

function TextInput:cursorBlinks(bool) --yes or no
    
end

function TextInput:cursorBlinkTime(num) --some amount of time inbetween blinks, default 1

end

function TextInput:getLine(x, y) --returns the string that's currently displayed (at the specified position if provideed)

end

function TextInput:draw()
    if (not self:visible()) then return end
    local oldFgColor = gpu.setForeground(self:foregroundColor())
    local oldBgColor = gpu.getBackground()
    if (self:backgroundColor()) then
        gpu.setBackground(self:backgroundColor())
        gpu.fill(self:absX(), self:absY(), self:width(), self:height(), " ")
    end
    local y, maxWidth = self:absY(), self:maxWidth()
    for i, line in ipairs(wrap(self:text(), maxWidth)) do
        ---@cast line string
        if ((y - self:absY()) + 1 <= self:maxHeight()) then
            local x = self:absX()
            --[[if (self:center() and self:minWidth() == self:maxWidth()) then
                x = x + (self:width() - #line) / 2
            end]]
            for c in line:gmatch(".") do
                local s, _, _, bg = pcall(gpu.get, x, y)
                if (s ~= false) then
                    gpu.setBackground(bg)
                    gpu.set(x, y, self:placeholder() or c)
                    x = x + 1
                end
            end
        end
        y = y + 1
    end
    gpu.setForeground(oldFgColor)
    gpu.setBackground(oldBgColor)
    return true
end

return TextInput
