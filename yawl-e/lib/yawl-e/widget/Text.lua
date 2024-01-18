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
    if not self:visible() then return end
    local isBordered = self:bordered()
    local x, y, width, height = self:absX() + (isBordered and 1 or 0), self:absY() + (isBordered and 1 or 0), self:width() + (isBordered and -2 or 0), self:height() + (isBordered and -2 or 0)
    -- local maxWidth, maxHeight --= self:maxWidth(), self:maxHeight()
    if height == 0 or width == 0 then return end
    local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()
    local parent = self:getParent()
    local newBG, newFG = self:backgroundColor() or (parent and parent:backgroundColor()), self:foregroundColor()
    if newBG then  --could use self:parent():backgroundColor()
        gpu.setBackground(newBG)
        self:_gpufill(x, y, width, height, " ")
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
        
        
    if yOff == 0 and height%textheight>0 and not (height%2>0 and textheight%2>0) then
        yStart = yStart + 1
    end
    if not isBordered and yOff == 1 and (height-1)%3==0 then 
        yStart = yStart + 1
    end
    --ugly and complicated, but it seems to work
    if height > 1 or textheight > 1 then
        local i, relativeX, relativeY, maxY = 1, 0, 0, y+height
        local str = self._parsedText[i]
        while yStart+relativeY+1 <= maxY and str and yStart+textheight>=y do
            if str then
                relativeX, relativeY = (xAlign == "center" and 0.5*(xSection-unicode.len(str))) or (xAlign == "right" and (xSection-unicode.len(str)-1)) or 0, i-1
                
                if yStart+relativeY >= y then
                    self:_gpuset(xStart+relativeX, yStart+relativeY, str) --, self._tweenSize~=nil or self._tweenPos~=nil)
                    
                end
                i=i+1
            end
            str = self._parsedText[i]
        end
    else
        local str = self:text():gsub("\n","")
        self:_gpuset(x, y, str, true)
    end
    
    gpu.setForeground(oldFG)
    gpu.setBackground(oldBG)
    return true
end

return Text
