local gpu = require("component").gpu
local Widget = require("yawl-e.widget.Widget")
local unicode = require("unicode")
---@class ProgressBar:Widget
---@overload fun(parent:Frame,x:number,y:number,width:number,height:number,min:number|nil,max:number|nil,backgroundColor:number|nil,foregroundColor:number|nil):ProgressBar
local ProgressBar = require("libClass2")(Widget)
ProgressBar:_borderOverride(true)
---@param parent Frame
---@param x number
---@param y number
---@param width number
---@param height number
---@param min? number
---@param max? number
---@param backgroundColor? number
---@param foregroundColor? number
---@return ProgressBar
function ProgressBar:new(parent, x, y, width, height, backgroundColor, foregroundColor)
    checkArg(1, parent, 'table')
    checkArg(2, x, 'number')
    checkArg(3, y, 'number')
    checkArg(4, width, 'number')
    checkArg(5, height, 'number')
    checkArg(6, backgroundColor, 'number', 'nil')
    checkArg(6, foregroundColor, 'number', 'nil')
    local o = self.parent(parent, x, y)
    setmetatable(o, {__index = self})
    o._size = {width = 1, height = 1}
    ---@cast o ProgressBar
    o:size(width, height) --probably need to override the size so minimum is 1x1
    o:value(0)
    o:backgroundColor(backgroundColor)
    o:foregroundColor(foregroundColor)
    return o
end

---@param value? number
---@return number
function ProgressBar:value(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._value
    if (value ~= nil) then self._value = math.max(math.min(1, value), 0) end
    return oldValue
end

---@param value? string
---@return string
function ProgressBar:fillChar(value)
    checkArg(1, value, 'string', 'nil')
    local oldValue = self._fillchar
    if (value ~= nil) then self._fillchar = unicode.charAt(value, 1) end
    return oldValue
end

---@param value? number
---@return number
function ProgressBar:fillBackgroundColor(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._fillBackgroundColor
    if (value) then self._fillBackgroundColor = value end
    return oldValue
end

---Increment or decrement the value
---@param value? number
---@return number
function ProgressBar:adjust(value)
    checkArg(1, value, 'number')
    return self:value(self:value() + value)
end
--TODO: add "fillDirection" so that bars can be vertical up/down as well as left/right
function ProgressBar:draw()
    if (not self:visible()) then return end
    local x, y, width, height = self:absX(), self:absY(), self:width(), self:height()
    local value = self:value()
    local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()
    local newBG, newFG = self:backgroundColor(), self:foregroundColor()
    local fillBG = self:fillBackgroundColor()
    if newBG then gpu.setBackground(newBG) end
    gpu.fill(x, y, width, height, " ") --overwrite the background
    
    if value and value>0 then
        local percent = math.floor(0.5 + ((width - 1) * (value / 1))) --rounded, might not need -1    
        if newFG then gpu.setForeground(newFG) end
        if fillBG then gpu.setBackground(fillBG) end
        local fillChar = self:fillChar() or " "
        gpu.fill(x , y, percent, height, fillChar) --might make funny tall slider
        --custom border
        local isBordered, borderSet = self:bordered(), self:borderSet()
        if newBG and isBordered and borderSet and width > 1 and height > 1 and fillChar == " " and fillBG and percent > 1 then
            local setLength = unicode.len(borderSet)
            if setLength > 3 then
                gpu.set(x, y, unicode.charAt(borderSet, 1))                                         --topleft
                gpu.set(x, y + height - 1, unicode.charAt(borderSet, 3))                            --bottomleft
                if setLength > 4 then
                    local isSix = setLength == 6
                    gpu.fill(x, y + 1, 1, height - 2, unicode.charAt(borderSet, isSix and 6 or 7))             --left
                    if percent >= width - 1 then
                        gpu.fill(x + 1, y, width - 2, 1, unicode.charAt(borderSet, 5))                  --top
                        gpu.fill(x + 1, y + height - 1, width - 2, 1, unicode.charAt(borderSet, isSix and 5 or 6)) --bottom
                    else
                        gpu.fill(x + 1, y, percent - 1, 1, unicode.charAt(borderSet, 5))                  --top
                        gpu.fill(x + 1, y + height - 1, percent - 1, 1, unicode.charAt(borderSet, isSix and 5 or 6)) --bottom
                        gpu.setBackground(newBG)
                        gpu.fill(x + percent, y, (width - 1 ) - percent, 1, unicode.charAt(borderSet, 5)) --top
                        gpu.fill(x + percent, y + height - 1, (width - 1 ) - percent, 1, unicode.charAt(borderSet, isSix and 5 or 6)) --bottom
                    end
                    if percent == width then gpu.setBackground(fillBG) end
                    gpu.fill(x + width - 1, y + 1, 1, height - 2, unicode.charAt(borderSet, isSix and 6 or 8)) -- right
                end
                gpu.set(x + width - 1, y, unicode.charAt(borderSet, 2, 2))                             --topright
                gpu.set(x + width - 1, y + height - 1, unicode.charAt(borderSet, 4))                --bottomright
            end
            if oldFG then gpu.setForeground(oldFG) end
            
            if newFG then gpu.setForeground(oldFG) end
        else
            self:drawBorder()
        end
    else
        self:drawBorder() --use default
    end
    gpu.setBackground(oldBG)
    return true
end

return ProgressBar
