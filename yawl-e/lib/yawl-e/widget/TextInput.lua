local event = require("event")
local unicode = require("unicode")
local class = require("libClass2")
local Text = require("yawl-e.widget.Text")
local gpu = require("component").gpu
local computer = require"computer"

--[[
    TODO
        add listener for paste event
        add auto-scroll and auto-size in _onKeyDown
            :scrollWithCursor()
            :dynamicWidth()
            :dynamicHeight()
            :minimumWidth()
            :minimumHeight()
            :widthRange()
            :heightRange()
            :maximumWidth()
            :maximumHeight() 
        fix/finish goofy behavior in _onKeyDown (which is nothing but agony)
]]

---@class TextInput:Text
---@field private _listeners.keyDownEvent number
---@field private _listeners.touchEvent number
---@operator call:TextInput
---@overload fun(parent:Frame,x:number,y:number,text:string,foregroundColor:number):TextInput
local TextInput = class(Text)

function TextInput:_onKeyDown(eventName, component, char, key, player)
    local cText = self:text()
    local cLength = unicode.len(cText)
    if (char == 8 or key == 211) then --backspace & delete
        local cX, cY = self:cursorXY()
        local index = self:cursor()- (cY > 1 and 1 or 0)
        local lineLength = unicode.len(self._parsedText[cY])
        if cLength > 0 then -- not too sure yet how good this is with multiline support but it fixed single line
            local cX, cY = self:cursorXY()
            local index = self:cursor() - (cY > 1 and 1 or 0)
        
            if char == 8 then -- Backspace
                if cX > 1 or cY > 1 then
                    local prevLineLen = cY > 1 and unicode.len(self._parsedText[cY - 1]) or 0
                    self:text(unicode.sub(cText, 1, index - 1) .. unicode.sub(cText, index + 1))
                    if cX == 1 then
                        cY = cY - 1
                        cX = prevLineLen + 1
                    else
                        cX = cX - 1
                    end
                end
            elseif key == 211 then -- Delete
                if index < cLength then -- Check to avoid deleting when at end
                    self:text(unicode.sub(cText, 1, index) .. unicode.sub(cText, index + 2))
                    -- No need to adjust cX for delete as the cursor stays in place
                end
            end
            self:cursorXY(cX, cY)
        end
    elseif (char==0 and (key==200 or key==203 or key == 205 or  key == 208)) then --arrow keys
        local cX, cY = self:cursorXY()
        if key == 203 then -- Left
            cX = math.max(1, cX - 1)
        elseif key == 205 then -- Right
            cX = math.min(unicode.len(self._parsedText[cY]) + 1, cX + 1)
        elseif key == 200 then -- Up
            cY = math.max(1, cY - 1)
        elseif key == 208 then -- Down
            cY = math.min(#self._parsedText, cY + 1)
        end
        self:cursorXY(cX, cY)
    elseif (char == 13) then --return
        if self:multilines() then
            local index = self:cursor()
            local cX, cY = self:cursorXY()
            local cText = self:text()
            self:text(unicode.sub(cText, 0, index-1) .. "\n" .. unicode.sub(cText, index))
            table.insert(self._parsedText,"")
            self:cursorXY(1, cY+1)
        else
            event.cancel(self._listeners.keyDownEvent)
            self._listeners.keyDownEvent = nil
            self._player = nil
            event.cancel(self._listeners.touchEvent)
            self._listeners.touchEvent = nil
        end
    elseif char>=32 and char<=126 then --normal characters
        if (self:height() == 1 and cLength < self:width()) or self:height() > 1 then
            local cX, cY = self:cursorXY()
            local index = self:cursor() - (cY > 1 and 1 or 0)
            local cText = self:text()
            -- if cX == 1 then index = index - 1 end
            self:text(unicode.sub(cText, 0, index) .. string.char(char) .. unicode.sub(cText, index + 1))
            if cX+1 > unicode.len(self._parsedText[cY]) then cY = cY + 1 end
            self:cursor(cX + 1, cY)
        end
    end
    -- self._debug:text(self:text())
    -- local cX, cY = self:cursorXY()
    -- local ctext = self:text()
    -- if self._debug then self._debug:text(require"computer".uptime(),"cursor(i,x,y):",self:cursor(), cX, cY,"|length:",unicode.len(ctext), unicode.charAt(ctext, self:cursor())) end
end

function TextInput:clearOnEnter(should)
    checkArg(1, should, 'boolean', 'nil')
    local oldValue = self._clearOnEnter 
    if oldValue == nil then self._clearOnEnter = false end
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
        self._listeners.keyDownEvent = event.listen("key_down", function(...) 
            local _, screen, _, _, plr = ...
            if not self._player then self._player = plr end
            if self._player == plr then
                self:_onKeyDown(...) 
            end
        end) --[[@as number]]
        self._listeners.touchEvent = event.listen("touch", function(eventName, uuid, x, y, button, playerName)
            if (not self:checkCollision(x, y)) then
                if (self._listeners.keyDownEvent) then event.cancel(self._listeners.keyDownEvent --[[@as number]]) end
                self._listeners.keyDownEvent = nil
                self._player = nil
                if (self._listeners.touchEvent) then event.cancel(self._listeners.touchEvent --[[@as number]]) end
                self._listeners.touchEvent = nil
                if self:clearOnEnter() then self:text("") end
            end
        end) --[[@as number]]
    end
    if self:height() == 1 and button == 0 then -- not finished for multiline support
        self:cursorXY(x - self:absX() + 1, 1)
    end
    return true
end

---@param value? boolean
---@return boolean
function TextInput:multilines(value)
    checkArg(1, value, 'boolean', 'nil')
    local oldValue = self._multilines or false
    if self._multilines == nil and self:height() > 1 then oldValue = true end
    if (value ~= nil) then self._multilines = value end
    return oldValue
end

function TextInput:_parse(override)
    checkArg(1, override, 'number', 'nil')
    local width = self:width()
    local xOff, yOff = self:textOffset()
    self._parsedText = {} --wrap(self:text(), override or self:wrapWidth() or (width - (((xOff or 0)+1) * math.floor(0.5 + width / 3)) ))
    local wrappedWith = override or self:wrapWidth() or (width - (((xOff or 0)+1) * math.floor(0.5 + width / 3)) )
    local inputText = self:text()
    for i=1, math.ceil(unicode.len(inputText)/wrappedWith) do
        table.insert(self._parsedText, unicode.sub(inputText, (i-1) * wrappedWith + 1, i*wrappedWith))
    end

    self:_calculateHighlights()
end

function TextInput:cursor(x, y) --if x and y, x specifies the char on the line y points to, if just x, it's the char at the index in the normal string
    checkArg(1, x, 'number', 'nil')
    checkArg(2, y, 'number', 'nil')
    local oldValue = self._cursor and self._cursor.index or 0
    if x and y then
        self:cursorXY(x, y)
    elseif x then
        x = math.max(1, x)
        self._cursor = self._cursor or {}
        local totalLength = 0
        local targetLine = 1
        local targetColumn = x

        -- Iterate through each line to find the line and column corresponding to x.
        for i, line in ipairs(self._parsedText) do
            local lineLength = unicode.len(line)
            if totalLength + lineLength >= x then
                -- Calculate column relative to this line, adjust for 1-based indexing.
                targetLine, targetColumn = i, x - totalLength
                break
            end
            totalLength = totalLength + lineLength + 1  -- Assuming newline characters between lines.
        end

        -- Ensure the targetColumn does not exceed the length of the line.
        targetColumn = math.min(targetColumn, unicode.len(self._parsedText[targetLine]))

        -- Update the cursor position.
        self:cursorXY(targetColumn, targetLine)
    end
    return oldValue
end

function TextInput:cursorXY(x,y) --if x and y, x specifies the char on the line y points to
    checkArg(1, x, 'number', 'nil')
    checkArg(1, y, 'number', 'nil')
    local oldValueY = self._cursor and self._cursor.y or 1
    local oldValueX = self._cursor and self._cursor.x or 1
    if x and y then
        self._cursor = self._cursor or {}
        -- Ensure y is within the bounds of the text.
        y = math.max(1, math.min(y, #self._parsedText))
        -- Ensure x is within the bounds of the line, including handling lines without a trailing newline.
        local lineLength = unicode.len(self._parsedText[y])
        --need to check against the wrap width here
        x = math.max(1, math.min(x, lineLength + (lineLength > 0 and 1 or 0)))

        self._cursor.y = y
        self._cursor.x = x

        -- Recalculate the cursor index based on the new x and y.
        local newIndex = 0
        for i = 1, y - 1 do
            newIndex = newIndex + unicode.len(self._parsedText[i])  + 1
        end
        self._cursor.index = math.max(newIndex + x - 1, 0)
        if self._cursor.y ~= oldValueY or self._cursor.x ~= oldValueX then
            self:invokeCallback("cursorChanged", self._cursor.index, x, y)
        end
    end
    return oldValueX, oldValueY
end

local defaultCursor = unicode.char(0x23B8)
function TextInput:cursorChar(char)
    checkArg(1, char, 'boolean', 'nil')
    local oldValue = self._cursorchar or false
    if (char ~= nil) then self._cursorchar = char end
    return oldValue
end


function TextInput:append(str) --inserts at the current cursor position

end

function TextInput:backspace(num) --how many characters to the left or right of the cursor to delete

end

function TextInput:cursorBlinks(bool) --yes or no
    checkArg(1, bool, 'boolean', 'nil')
    local oldValue = self._shouldblink
    if oldValue == nil then oldValue = true end
    if (bool ~= nil) then self._shouldblink = bool end
    return oldValue
end

function TextInput:cursorBlinkTime(num) --some amount of time inbetween blinks, default 1
    checkArg(1, num, 'number', 'nil')
    local oldValue = self._blinkTime or 1
    if num then self._blinkTime = num end
    return oldValue
end

function TextInput:getLine(x, y) --returns the string that's currently displayed (at the specified position if provideed)

end

function TextInput:deleteLine(y) --uses cursor Y if not provided

end

function TextInput:draw()if not self:visible() then return end
    local isBordered = self:bordered()
    local x, y, width, height = self:absX() + (isBordered and 1 or 0), self:absY() + (isBordered and 1 or 0), self:width() + (isBordered and -2 or 0), self:height() + (isBordered and -2 or 0)
    local maxWidth, maxHeight --= self:maxWidth(), self:maxHeight()
    if height == 0 or width == 0 then return end
    local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()
    local parent = self:getParent()
    local newBG, newFG = self:backgroundColor() or (parent and parent:backgroundColor()), self:foregroundColor()
    if newBG then  --could use self:parent():backgroundColor()
        gpu.setBackground(newBG)
        self:_gpufill(x, y, width, height, " ", true)
    end
    if newFG then gpu.setForeground(newFG) end

    local textheight = #self._parsedText
    local xScroll, yScroll = self:scrollX(), self:scrollY()
    local xOff, yOff = self:textOffset()
    local xSection = math.floor(0.5 + width  / 3)
    local ySection = math.floor(0.5 + height / 3)
    local xAlign, yAlign = self:textHorizontalAlignment(), self:textVerticalAlignment()
    local xStart, yStart = xScroll + x+(xOff+1)*xSection, 
        ((yAlign == "center" and 0.5*(ySection-textheight)) or
        (yAlign == "bottom" and (ySection-textheight)) or 0) ---
        + (yScroll + y + ((yOff+1) * ySection))
        
    if ( height%2>0 and textheight%2>0 and yOff == 0) or (not isBordered and yOff == 1 and (height-1)%3==0) then 
        yStart = yStart + 1
    end
    -- if textheight == 0 then return end
    --ugly and complicated, but it seems to work
    local blinkTime = self:cursorBlinkTime()
    local cursorBlinks, cursorChar = self:cursorBlinks(), self:cursorChar()
    local cursorX, cursorY = self:cursorXY()
    -- if height > 1 or textheight > 1 then
        local i, relativeX, relativeY, maxY = 1, 0, 0, y+height
        local str = self._parsedText[i]
        local currentY = yStart+relativeY
        while (currentY+(textheight>1 and 1 or 0)) < maxY and str and yStart+textheight>=y do
            if str then
                relativeX, relativeY = (xAlign == "center" and 0.5*(xSection-unicode.len(str))) or (xAlign == "right" and (xSection-unicode.len(str)-1)) or 0, i-1
                currentY = yStart+relativeY
                if currentY >= y then
                    self:_gpuset(xStart+relativeX, currentY, str, true)
                    if self._listeners.keyDownEvent and i == cursorY then
                        --cursorBlinks, uses time to optionally show cursor, otherwise always shows
                        if str then
                            cursorChar = unicode.charAt(str, cursorX)
                            if newFG and (cursorChar~=" " and cursorChar~="") then gpu.setBackground(0xffffff-newFG) end
                        end
                        local now = computer.uptime()
                        if cursorBlinks then
                            if (now-(self._lastBlinked or 0))>=blinkTime then
                                self._lastBlinked = now
                                self._blinkBoolean = not self._blinkBoolean
                                self:invokeCallback("cursorBlinked", self._blinkBoolean)
                            end
                            if self._blinkBoolean then
                                cursorChar = defaultCursor
                            end
                        end
                        if cursorChar == "" or cursorChar == " " or cursorChar == nil then 
                            cursorChar = defaultCursor
                        end
                        
                        -- 
                        self:_gpuset(xStart + relativeX + cursorX - 1, currentY, cursorChar, true )
                        gpu.setBackground(newBG or oldBG)
                    end
                end
                i=i+1
            end
            str = self._parsedText[i]
        end
    -- else
    --     local str = self:text():gsub("\n","")
    --     self:_gpuset(x, y, str, true)
    -- end

    gpu.setForeground(oldFG)
    gpu.setBackground(oldBG)
    return true
end

return TextInput
