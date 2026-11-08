local checkArg = require("loom.util").checkArg
local unicode = require("unicode")
local computer = require("computer")
local gpu = require("loom.gpu")
local input = require("loom.input")
local run = require("loom.run")
local Widget = require("loom.widget.Widget")

local usub, ulen = unicode.sub, unicode.len

---An editable text field. Touch it (or Tab to it) to type. The text is a string plus a cursor
---index; single-line fields scroll sideways, multiline fields split on newlines and scroll both ways.
---
---Keys: arrows, Home/End (Ctrl for the whole text), Ctrl+Left/Right by word, Backspace/Delete
---(Ctrl for a word), Enter submits (inserts a newline in a multiline field; Ctrl+Enter submits),
---Tab/Shift+Tab move focus, Escape leaves the field. Pasting inserts the clipboard.
---
---Events passed to the callback and to `on` handlers: "valueChanged" (old, new), "submit" (text),
---"focus", "blur", "cursorChanged" (index, x, y), and the screen events.
---@class TextInput:Widget
---@operator call:TextInput
---@overload fun(parent:Frame,x:number,y:number,text?:string,foregroundColor?:number):TextInput
local TextInput = require("loom.class")(Widget)

---@param parent Frame
---@param x number
---@param y number
---@param text? string
---@param foregroundColor? number
---@return TextInput
function TextInput:new(parent, x, y, text, foregroundColor)
    checkArg(4, text, 'string', 'nil')
    checkArg(5, foregroundColor, 'number', 'nil')
    local o = self.parent(parent, x, y)
    setmetatable(o, self)
    ---@cast o TextInput
    o._text = text or ""
    o._cursor = ulen(o._text)
    o._foregroundColor = foregroundColor or 0xffffff
    return o
end

---Set the text (the arguments are joined with spaces) and put the cursor at its end. Return the old text.
---@param ... any
---@return string
function TextInput:text(...)
    local old = self._text
    if ... ~= nil then
        local values = table.pack(...)
        for i = 1, values.n do values[i] = tostring(values[i]) end
        self:_set(table.concat(values, " ", 1, values.n), math.huge)
    end
    return old
end

---Replace the text and cursor, clamping the cursor, and tell the callback.
---@private
function TextInput:_set(text, cursor)
    local old = self._text
    local length = ulen(text)
    local max = self._maxLength
    if max and length > max then text, length = usub(text, 1, max), max end
    self._text, self._lines = text, nil
    local oldCursor = self._cursor
    self._cursor = math.max(0, math.min(cursor, length))
    self._blink = computer.uptime() -- show the cursor while typing
    if text ~= old then self:invokeCallback("valueChanged", old, text) end
    if self._cursor ~= oldCursor then
        local x, y = self:cursorXY()
        self:invokeCallback("cursorChanged", self._cursor, x, y)
    end
end

---The text split into the lines shown. Single-line fields have one line.
---@private
---@return string[]
function TextInput:_lineList()
    local lines = self._lines
    if not lines then
        if self:multilines() then
            lines = {}
            for line in (self._text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
        else
            lines = {self._text}
        end
        self._lines = lines
    end
    return lines
end

---Line and column of a text index (0 = before the first character).
---@private
function TextInput:_lineCol(index)
    local lines = self:_lineList()
    for i, line in ipairs(lines) do
        local length = ulen(line)
        if index <= length then return i, index + 1 end
        index = index - length - 1
    end
    return #lines, ulen(lines[#lines]) + 1
end

---Text index of a line and column, clamped to the text.
---@private
function TextInput:_index(line, column)
    local lines = self:_lineList()
    line = math.max(1, math.min(line, #lines))
    local index = 0
    for i = 1, line - 1 do index = index + ulen(lines[i]) + 1 end
    return index + math.max(1, math.min(column, ulen(lines[line]) + 1)) - 1
end

---Get or set the cursor as a text index (0 = before the first character).
---With two arguments, set it by column and line like `cursorXY`.
---@param x? number
---@param y? number
---@return number
function TextInput:cursor(x, y)
    checkArg(1, x, 'number', 'nil')
    checkArg(2, y, 'number', 'nil')
    local old = self._cursor
    if x and y then self:cursorXY(x, y)
    elseif x then self:_set(self._text, x) end
    return old
end

---Get or set the cursor as a column and line.
---@param x? number
---@param y? number
---@return number x,number y
function TextInput:cursorXY(x, y)
    checkArg(1, x, 'number', 'nil')
    checkArg(2, y, 'number', 'nil')
    local oldY, oldX = self:_lineCol(self._cursor)
    if x and y then self:_set(self._text, self:_index(y, x)) end
    return oldX, oldY
end

---Insert `str` at the cursor. Single-line fields drop a trailing newline and turn others into spaces.
---@param str string
function TextInput:insert(str)
    checkArg(1, str, 'string')
    if not self:multilines() then str = str:gsub("\r?\n$", ""):gsub("\r?\n", " ") end
    local max, length = self._maxLength, ulen(str)
    if max then
        length = math.max(0, math.min(length, max - ulen(self._text)))
        str = usub(str, 1, length)
    end
    if length == 0 then return end
    local text, c = self._text, self._cursor
    self:_set(usub(text, 1, c) .. str .. usub(text, c + 1), c + length)
end

local function isWord(char) return #char > 1 or char:find("^[%w_]") ~= nil end

---Index reached by jumping a word left (dir -1) or right (dir 1) from the cursor.
---@private
function TextInput:_wordFrom(dir)
    local text, i = self._text, self._cursor
    local length = ulen(text)
    if dir < 0 then
        while i > 0 and not isWord(usub(text, i, i)) do i = i - 1 end
        while i > 0 and isWord(usub(text, i, i)) do i = i - 1 end
    else
        while i < length and not isWord(usub(text, i + 1, i + 1)) do i = i + 1 end
        while i < length and isWord(usub(text, i + 1, i + 1)) do i = i + 1 end
    end
    return i
end

---Delete from the cursor to index `to`.
---@private
function TextInput:_deleteTo(to)
    local text, c = self._text, self._cursor
    local a, b = math.max(0, math.min(c, to)), math.max(c, to)
    if a == b then return end
    self:_set(usub(text, 1, a) .. usub(text, b + 1), a)
end

---Submit the text: tell the callback, then clear the field (`clearOnEnter`) or leave it.
function TextInput:submit()
    self:invokeCallback("submit", self._text)
    if self:clearOnEnter() then self:_set("", 0) else self:blur() end
end

---Handle a key while focused.
---@private
function TextInput:_key(char, code, ctrl)
    local c, text = self._cursor, self._text
    local multi = self:multilines()
    local goal = self._goal
    self._goal = nil
    if code == 14 then -- Backspace
        self:_deleteTo(ctrl and self:_wordFrom(-1) or c - 1)
    elseif code == 211 then -- Delete
        self:_deleteTo(ctrl and self:_wordFrom(1) or c + 1)
    elseif code == 203 then -- Left
        self:_set(text, ctrl and self:_wordFrom(-1) or c - 1)
    elseif code == 205 then -- Right
        self:_set(text, ctrl and self:_wordFrom(1) or c + 1)
    elseif code == 199 or code == 207 then -- Home, End
        if ctrl or not multi then
            self:_set(text, code == 199 and 0 or math.huge)
        else
            local line = self:_lineCol(c)
            self:_set(text, self:_index(line, code == 199 and 1 or math.huge))
        end
    elseif (code == 200 or code == 208) and multi then -- Up, Down: keep the column across short lines
        local line, column = self:_lineCol(c)
        goal = goal or column
        local target = line + (code == 200 and -1 or 1)
        if target < 1 then self:_set(text, 0)
        elseif target > #self:_lineList() then self:_set(text, math.huge)
        else self:_set(text, self:_index(target, goal)) end
        self._goal = goal
    elseif code == 28 or code == 156 then -- Enter, keypad Enter
        if multi and not ctrl then self:insert("\n") else self:submit() end
    elseif char >= 32 and char ~= 127 and not ctrl then
        self:insert(unicode.char(char))
    end
end

---Handle a paste while focused.
---@private
function TextInput:_paste(text) self:insert(text) end

---Take the keyboard. `player`, if given, is the only player whose keys count.
---@param player? string
function TextInput:focus(player) input.focus(self, player) end

---Give the keyboard back.
function TextInput:blur()
    if input.focused() == self then input.focus(nil) end
end

---@return boolean
function TextInput:focused() return input.focused() == self end

---The area inside the border.
---@private
function TextInput:_inner()
    local b = self:bordered() and 1 or 0
    return self:absX() + b, self:absY() + b, self:width() - 2 * b, self:height() - 2 * b
end

function TextInput:invokeCallback(eventName, ...)
    if eventName == "touch" and self:enabled() then
        local _, x, y, button, player = ...
        if button == 1 then -- right click clears
            self:_set("", 0)
        else
            local ix, iy = self:_inner()
            self:_set(self._text, self:_index(y - iy + 1 + (self._scrollY or 0), x - ix + 1 + (self._scrollX or 0)))
        end
        self:focus(player)
        Widget.invokeCallback(self, eventName, ...)
        return true
    elseif eventName == "blur" then
        self._scrollX = 0 -- show the start of the text again
    end
    return Widget.invokeCallback(self, eventName, ...)
end

---Clear the field after submit (Enter) and keep typing, chat style. Otherwise Enter leaves the field.
---@param should? boolean
---@return boolean
function TextInput:clearOnEnter(should)
    checkArg(1, should, 'boolean', 'nil')
    local old = self._clearOnEnter or false
    if should ~= nil then self._clearOnEnter = should end
    return old
end

---Multiline fields take newlines and scroll both ways. Defaults to true for fields taller than one line.
---@param value? boolean
---@return boolean
function TextInput:multilines(value)
    checkArg(1, value, 'boolean', 'nil')
    local old = self._multilines
    if old == nil then old = self:height() > (self:bordered() and 3 or 1) end
    if value ~= nil then self._multilines, self._lines = value, nil end
    return old
end

---Longest text the field accepts. `false` removes the limit.
---@param value? number|false
---@return number|false
function TextInput:maxLength(value)
    checkArg(1, value, 'number', 'boolean', 'nil')
    local old = self._maxLength or false
    if value == false then self._maxLength = nil elseif value then self._maxLength = value end
    return old
end

---Text shown, dimmed, while the field is empty and not focused.
---@param text? string|false
---@param color? number
---@return string|false
function TextInput:placeholder(text, color)
    checkArg(1, text, 'string', 'boolean', 'nil')
    checkArg(2, color, 'number', 'nil')
    local old = self._placeholder or false
    if text == false then self._placeholder = nil elseif text then self._placeholder = text end
    if color then self._placeholderColor = color end
    return old
end

---Show every character as `char`, for passwords. `false` shows the text again.
---@param char? string|false
---@return string|false
function TextInput:mask(char)
    checkArg(1, char, 'string', 'boolean', 'nil')
    local old = self._mask or false
    if char == false then self._mask = nil elseif char then self._mask = char end
    return old
end

---@param bool? boolean
---@return boolean
function TextInput:cursorBlinks(bool)
    checkArg(1, bool, 'boolean', 'nil')
    local old = self._shouldblink
    if old == nil then old = true end
    if bool ~= nil then self._shouldblink = bool end
    return old
end

---Seconds the cursor stays shown, then hidden, while blinking.
---@param num? number
---@return number
function TextInput:cursorBlinkTime(num)
    checkArg(1, num, 'number', 'nil')
    local old = self._blinkTime or 0.5
    if num then self._blinkTime = num end
    return old
end

function TextInput:draw()
    if not self:visible() then return end
    local x, y, width, height = self:_inner()
    if width < 1 or height < 1 then return end
    input.shown(self)
    local parent = self:getParent()
    local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()
    local bg = self:backgroundColor() or (parent and parent:backgroundColor()) or oldBG
    local fg = self:foregroundColor() or 0xffffff
    gpu.setBackground(bg)
    gpu.setForeground(fg)
    self:_gpufill(x, y, width, height, " ")
    local focused = input.focused() == self
    if self._text == "" and not focused and self._placeholder then
        gpu.setForeground(self._placeholderColor or 0x888888)
        self:_gpuset(x, y, self._placeholder)
    else
        -- while focused, scroll so the cursor stays in view
        local line, column = self:_lineCol(self._cursor)
        local sx, sy = self._scrollX or 0, self._scrollY or 0
        if focused then
            if column - 1 < sx then sx = column - 1 elseif column - sx > width then sx = column - width end
            if line - 1 < sy then sy = line - 1 elseif line - sy > height then sy = line - height end
            self._scrollX, self._scrollY = sx, sy
        end
        local lines, mask = self:_lineList(), self._mask
        for row = 1, height do
            local str = lines[sy + row]
            if not str then break end
            str = usub(str, sx + 1, sx + width)
            if mask then str = mask:rep(ulen(str)) end
            self:_gpuset(x, y + row - 1, str)
        end
        if focused then
            local shown = true
            if self:cursorBlinks() then
                local period, elapsed = self:cursorBlinkTime(), computer.uptime() - (self._blink or 0)
                shown = elapsed % (2 * period) < period
                run.request(period - elapsed % period)
            end
            if shown then
                local char = usub(lines[line], column, column)
                if char == "" then char = " " elseif mask then char = mask end
                gpu.setBackground(fg)
                gpu.setForeground(bg)
                self:_gpuset(x + column - 1 - sx, y + line - 1 - sy, char)
            end
        end
    end
    gpu.setForeground(oldFG)
    gpu.setBackground(oldBG)
    return true
end

function TextInput:Destroy(force)
    input.forget(self)
    return Widget.Destroy(self, force)
end

return TextInput
