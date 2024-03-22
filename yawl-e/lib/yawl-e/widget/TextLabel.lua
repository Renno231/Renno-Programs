--[[
    a much much simpler and cheaper and lighter Text object without any line wrapping
    true to its name, it's purely for being able to show a simple 1 line text
    height is never above 1 line
]]
local gpu = require("component").gpu
local unicode = require("unicode")

local Widget = require("yawl-e.widget.Widget")
local TextLabel = require('libClass2')(Widget)

---@param parent Frame
---@param x number
---@param y number
---@param text string
---@param foregroundColor number
---@return Text
function TextLabel:new(parent, x, y, text, foregroundColor)
    checkArg(1, parent, 'table')
    checkArg(2, x, 'number', 'table')
    checkArg(3, y, 'number', 'nil')
    checkArg(4, text, 'string', 'nil')
    checkArg(5, foregroundColor, 'number', 'nil')
    if (type(x) == "table") then checkArg(3, y, 'nil') else checkArg(3, y, 'number') end
    local o = self.parent(parent, x, y)
    setmetatable(o, {__index = self})
    ---@cast o Text
    o:text(text or "")
    o:foregroundColor(foregroundColor or 0xffffff)
    return o
end

---@param value? string
---@return string
function TextLabel:text(...)
    local oldValue = self._text
    if ...~=nil then
        local values = {...}
        for i,v in ipairs (values) do --table.concat bugs out sometimes
            values[i] = tostring(v)
        end
        self._text = table.concat(values, " "):gsub("\n","")
        
        if oldValue ~= self._text then self:invokeCallback("valueChanged", oldValue, self._text) end
        if self:autoWidth() then
            self:width(unicode.len(self._text))
        end
    end
    return oldValue
end

function TextLabel:height(value)
    checkArg(1, value, "number", "nil")
    local oldValue = self._size.height
    if value then
        self._size.height = math.min(self:bordered() and 3 or 1, value) -- overrided height
        
        if oldValue ~= self._size.height then self:invokeCallback("heightChanged", oldValue, self._size.height) end
    end
    return oldValue
end

function TextLabel:autoWidth(value)
    checkArg(1, value, "boolean", 'nil')
    local oldValue = self._autoWidthOnText
    if oldValue == nil then oldValue = true end
    if value~=nil then
        self._autoWidthOnText = value
    end
    return oldValue
end

function TextLabel:draw()
    if not self:visible() then return end
    local isBordered = self:bordered()
    local x, y = self:absX() + (isBordered and 1 or 0), self:absY() + (isBordered and 1 or 0)
    local width, height = self:width() + (isBordered and -2 or 0), self:height() + (isBordered and -2 or 0)
    if height == 0 or width == 0 then return end

    local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()
    local parent = self:getParent()
    local newBG, newFG = self:backgroundColor() or (parent and parent:backgroundColor()), self:foregroundColor()
    if newBG then  --could use self:parent():backgroundColor()
        gpu.setBackground(newBG)
        self:_gpufill(x, y, width, height, " ", true)
    end
    if newFG then gpu.setForeground(newFG) end
    self:_gpuset(x, y, self:text())
    
    gpu.setForeground(oldFG)
    gpu.setBackground(oldBG)
    return true
end


return TextLabel