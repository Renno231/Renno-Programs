local gpu = require("component").gpu
local wrap = require("yawl-e.util").wrap
local unicode = require("unicode")
--=============================================================================

local txtOffsets = {
    ["top left"] = {-1,-1},
    ["top center"] = {0,-1},
    ["top right"] = {1,-1},
    ["center left"] = {-1,0},
    ["center"] = {0,0},
    ["center right"] = {1,0},
    ["bottom left"] = {-1,1},
    ["bottom center"] = {0,1},
    ["bottom right"] = {1,1},
}

---@class Text:Widget
---@field private _text string
---@field private _foregroundColor number
---@field private _maxWidth number
---@field private _maxHeight number
---@overload fun(parent:Frame,x:number,y:number,text:string,foregroundColor:number):Text
---@operator call:Text
local Widget = require("yawl-e.widget.Widget")
local Text = require('libClass2')(Widget)

---@param parent Frame
---@param x number
---@param y number
---@param text string
---@param foregroundColor number
---@return Text
function Text:new(parent, x, y, text, foregroundColor)
    checkArg(1, parent, 'table')
    checkArg(2, x, 'number', 'table')
    checkArg(3, y, 'number', 'nil')
    checkArg(4, text, 'string')
    checkArg(5, foregroundColor, 'number', 'nil')
    if (type(x) == "table") then checkArg(3, y, 'nil') else checkArg(3, y, 'number') end
    local o = self.parent(parent, x, y)
    setmetatable(o, {__index = self})
    ---@cast o Text
    o:text(text)
    o:textOffset("top left") --normal
    o:textHorizontalAlignment("left")
    o:textVerticalAlignment("top")
    o._parsedText = {}
    o._textHighlights = {normal = {}}
    o:foregroundColor(foregroundColor or 0xffffff)
    return o
end

---@param value? string
---@return string
function Text:text(...)
    local oldValue = self._text
    local values = {...}
    if #values > 0 then
        for i,v in ipairs (values) do --table.concat bugs out sometimes
            values[i] = tostring(v)
        end
        self._text = table.concat(values, " ")
        self:_parse()
    end
    return oldValue
end

function Text:textHighlight(fgcolor, bgcolor, start, finish, line)
    checkArg(1, fgcolor, 'number', 'table')
    checkArg(1, bgcolor, 'number', 'nil')
    checkArg(1, start, 'number', 'string', 'nil')
    checkArg(1, finish, 'number', 'nil')
    checkArg(1, line, 'number', 'nil')
    local oldValue = self._textHighlights -- making a getter is quite complicated for such a complex and niche thing, better to just expose this
    if type(fgcolor) == 'table' then --custom premade table
        self._textHighlights = fgcolor 
    elseif type(start) == 'string' and start~="_normal" then --match filter
        if finish == nil then
            self._textHighlights[start] = {fgcolor = fgcolor, bgcolor = bgcolor} 
        elseif finish == false then  --much easier to remove
            self._textHighlights[start] = nil
        end
    elseif type(start) == 'number' and type(finish) == "number" then --old fashioned start/finish
        local highlightInfo = {start = start, finish = finish, fgcolor = fgcolor, bgcolor = bgcolor}
        if line and self._textHighlights._normal then
            if self._textHighlights._normal[string.format("Line%s", line)]==nil then
                self._textHighlights._normal[string.format("Line%s", line)] = {}
            end
            table.insert(self._textHighlights._normal[string.format("Line%s", line)], highlightInfo)
        elseif self._textHighlights._normal then
            table.insert(self._textHighlights._normal, highlightInfo)
        end
    end
    self:_calculateHighlights()
    return oldValue
end

function Text:clearHighlights()
    self._textHighlights = {}
    self._textHighlights._normal = {}
    self._textHighlightResults = {}
    return true
end

---@param value? number
---@return number
function Text:maxWidth(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._maxWidth or math.huge
    if (value and value > self:maxHeight()) then error("maxWidth cannot be smaller than minWidth", 2) end
    if (value) then self._maxWidth = value end
    return oldValue
end

---@param value? number
---@return number
function Text:maxHeight(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._maxHeight or math.huge
    if (value and value > self:maxHeight()) then error("maxHeight cannot be smaller than minHeight", 2) end
    if (value) then self._maxHeight = value end
    return oldValue
end
--replace min/max stuff with :textWidth() for the wrap
---Set the Text's min size.
---@param maxWidth number
---@param maxHeight number
---@return Size
---@overload fun(self:Rectangle,size:Size):Size
---@overload fun(self:Rectangle):Size
function Text:maxSize(maxWidth, maxHeight)
    checkArg(1, maxWidth, 'number', 'table', 'nil')
    checkArg(2, maxHeight, 'number', 'nil')
    local oldPos = {width = self:maxWidth(), height = self:maxHeight()}
    if (type(maxWidth) == 'number') then
        self:maxWidth(maxWidth)
        self:maxHeight(maxHeight)
    elseif (type(maxWidth) == 'table') then
        checkArg(2, maxHeight, 'nil')
        self._size = maxWidth
    end
    return oldPos
end

---@param value? number
---@return number
function Text:minWidth(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._minWidth or 0
    if (value and value > self:maxWidth()) then self:maxWidth(value) end
    if (value) then self._minWidth = value end
    return oldValue
end

---@param value? number
---@return number
function Text:minHeight(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._minHeight or 0
    if (value and value > self:maxHeight()) then self:maxHeight(value) end
    if (value) then self._minHeight = value end
    return oldValue
end

---Set the Text's min size.
---@param minWidth number
---@param minHeight number
---@return Size
---@overload fun(self:Rectangle,size:Size):Size
---@overload fun(self:Rectangle):Size
function Text:minSize(minWidth, minHeight)
    checkArg(1, minWidth, 'number', 'table', 'nil')
    checkArg(2, minHeight, 'number', 'nil')
    local oldPos = {width = self:minWidth(), height = self:minHeight()}
    if (type(minWidth) == 'number') then
        self:minWidth(minWidth)
        self:minHeight(minHeight)
    elseif (type(minWidth) == 'table') then
        checkArg(2, minHeight, 'nil')
        self._size = minWidth
    end
    return oldPos
end

---@param value? number
---@return number
--[[function Text:height(value)
    local h = Widget.height(self, value)
    self._parsedText = wrap(self:text(), self:wrapWidth())
    return h
end]]

---@param value? number
---@return number
function Text:width(width)
    checkArg(1, width, 'number', 'nil')
    local oldValue = self._size.width
    if (width) then 
        self._size.width = width 
        self:_parse()
    end
    return oldValue
end

function Text:_parse(override)
    checkArg(1, override, 'number', 'nil')
    local width = self:width()
    local xOff, yOff = self:textOffset()
    self._parsedText = wrap(self:text(), override or self:wrapWidth() or (width - (((xOff or 0)+1) * math.floor(0.5 + width / 3)) ))
    self:_calculateHighlights()
end

--need to make it to where this can be done by match for * lines, or for a specified line
function Text:_calculateHighlights()
    if not self._textHighlights then return false end
    self._textHighlightResults = {}
    local flattenedText = self._text:gsub("\n","")
    for toMatch, data in pairs (self._textHighlights) do
        if toMatch ~= "_normal" then --shows "normal"????
            local searchStart = 1
            -- local lineIndexStart = 1 --debug
            local startIdx, endIdx = string.find(flattenedText, toMatch, searchStart)
            while startIdx do  
                local isContinuation = false
                local currentIndex = 0
                -- for i = lineIndexStart, #self._parsedText do
                    -- local line = self._parsedText[i]
                for i, line in ipairs(self._parsedText) do
                    local lineLength = #line
                    local lineStart, lineEnd

                    if currentIndex + lineLength >= startIdx and not isContinuation then
                        lineStart = startIdx - currentIndex
                        lineEnd = math.min(endIdx - currentIndex, lineLength)
                        isContinuation = currentIndex + lineLength < endIdx
                    elseif isContinuation then
                        lineStart = 1
                        lineEnd = math.min(endIdx - currentIndex, lineLength)
                    end

                    if lineStart and lineEnd then
                        -- lineIndexStart = math.max(i-1, 1)
                        table.insert(self._textHighlightResults, 
                        {lineNumber = i, line = line:sub(lineStart, lineEnd), lineStart = lineStart, fgcolor = data.fgcolor, bgcolor = data.bgcolor})
                    end
                    if currentIndex + lineLength >= endIdx then
                        -- searchIterations = searchIterations + 1
                        break
                    end
                    currentIndex = currentIndex + lineLength
                end
                searchStart = endIdx + (startIdx == endIdx and 1 or 0)
                startIdx, endIdx = string.find(flattenedText, toMatch, searchStart)
            end
        end
    end
    return true
end

function Text:wrapWidth(wrapw)
    checkArg(1, wrapw, 'number', 'nil')
    local oldValue = self._wrapwidth
    if wrapw then
        self._wrapwidth = wrapw
        self._parsedText = wrap(self:text(), wrapw)
    end
    return oldValue
end

---@param value? number
---@return number
function Text:textOffset(x, y)
    checkArg(1, x, 'number', 'string', 'nil')
    checkArg(1, y, 'number', 'nil')
    local oldValue = self._textoffset
    if type(x) == "string" and y == nil then
        if txtOffsets[x] then
            self._textoffset = {x = txtOffsets[x][1], y = txtOffsets[x][2]}
            self:_parse()
        end
    elseif x and y then 
        self._textoffset = {x = x, y = y}
        self:_parse()
    end
    return oldValue and oldValue.x, oldValue and oldValue.y
end

function Text:textHorizontalAlignment(xalignment)
    checkArg(1, xalignment, 'string', 'nil')
    local oldValue = self._horizalign
    if xalignment and (xalignment == 'left' or xalignment == 'center' or xalignment == 'right') then
        self._horizalign = xalignment
    end
    return oldValue
end

function Text:textVerticalAlignment(yalignment)
    checkArg(1, yalignment, 'string', 'nil')
    local oldValue = self._vertalign
    if yalignment and (yalignment == 'top' or yalignment == 'center' or yalignment == 'bottom') then
        self._vertalign = yalignment
    end
    return oldValue
end

function Text:textAlignment(xalignment, yalignment)
    checkArg(1, xalignment, 'string')
    checkArg(2, yalignment, 'string')
end

function Text:scrollX(num, override)
    checkArg(1, num, 'number', 'nil')
    checkArg(2, override, 'boolean','nil')
    local oldValue = self._scrollindexX or 0
    if (num) then self._scrollindexX = override and num or ((self._scrollindexX or oldValue) + num) end
    return oldValue
end

function Text:scrollY(num, override)
    checkArg(1, num, 'number', 'nil')
    checkArg(2, override, 'boolean','nil')
    local oldValue = self._scrollindexY or 0
    if (num) then self._scrollindexY = override and num or ((self._scrollindexY or oldValue) + num) end
    return oldValue
end


function Text:draw()
    -- could optimize this somewhat with a :isAsciiArt() method, which would basically just do a gpu.set directly and skip clipping checks
    if not self:visible() then return end
    local isBordered = self:bordered()
    local x, y = self:absX() + (isBordered and 1 or 0), self:absY() + (isBordered and 1 or 0)
    local width, height = self:width() + (isBordered and -2 or 0), self:height() + (isBordered and -2 or 0)
    
    -- local maxWidth, maxHeight --= self:maxWidth(), self:maxHeight()
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
    local xStart = xScroll + x + (xOff + 1) * xSection
    local yStart =  ((yAlign == "center" and 0.5*(ySection-textheight)) or
                    (yAlign == "bottom" and (ySection-textheight)) or 0) 
                    + (yScroll + y + ((yOff+1) * ySection))
                    
    if yOff == 0 and height%textheight>0 and not (height%2>0 and textheight%2>0) then
        yStart = yStart + 1
    end
    if not isBordered and yOff == 1 and (height-1)%3==0 then 
        yStart = yStart + 1
    end
    --ugly and complicated, but it seems to work
    local storedRelativeX = {}
    if height > 1 or textheight > 1 then
        local i, relativeX, relativeY, maxY = 1, 0, 0, y+height
        local str = self._parsedText[i]
        while yStart+relativeY+1 <= maxY and str and yStart+textheight>=y do
            if str then
                relativeX = (xAlign == "center" and 0.5*(xSection-unicode.len(str))) or 
                            (xAlign == "right" and (xSection-unicode.len(str))) or 
                            0
                relativeX = math.floor(0.5 + relativeX)
                relativeY = i-1
                if yStart+relativeY >= y then
                    self:_gpuset(xStart+relativeX, yStart+relativeY, str)
                    storedRelativeX[i] = relativeX
                end
                i=i+1
            end
            str = self._parsedText[i]
        end
    else
        local str = self._text:gsub("\n","") --should probably store as self._flatText
        local relativeX =   (xAlign == "center" and 0.5*(xSection-unicode.len(str))) or 
                            (xAlign == "right" and (xSection-unicode.len(str))) or 
                            0
        if unicode.len(str)==width and xAlign == "center" then 
            xStart, relativeX = x, 0
        end
        -- if unicode.len(str) == width then relativeX = 0 end
        self:_gpuset(xStart + relativeX, y, str)
    end
    if self._textHighlightResults then
        for _, data in ipairs (self._textHighlightResults) do
            if storedRelativeX[data.lineNumber] then
                local highlightX = xStart + storedRelativeX[data.lineNumber] + (data.lineStart - 1)
                if data.fgcolor then gpu.setForeground(data.fgcolor) end
                if data.bgcolor then gpu.setBackground(data.bgcolor) end
                self:_gpuset(highlightX, yStart + data.lineNumber - 1, data.line )
                if newBG then gpu.setBackground(newBG) end
                if newFG then gpu.setForeground(newFG) end
            end
        end
    end
    gpu.setForeground(oldFG)
    gpu.setBackground(oldBG)
    return true
end

return Text
