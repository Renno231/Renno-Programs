local class = require("libClass2")
local Frame = require("yawl-e.widget.Frame")
local unicode = require("unicode")
local gpu = require("component").gpu

---@class Border:Frame
---@field parent Frame
---@operator call:Border
---@overload fun(parent:Frame,x:number,y:number,borderset:string):Border
---@overload fun(parent:Frame,x:number,y:number):Border
local Border = class(Frame)

---Comment
---@return Border
---@param parent Frame
---@param x number
---@param y number
---@param borderset? string
function Border:new(parent, x, y, borderset)
    checkArg(1, parent, "table")
    checkArg(1, borderset, "string", nil)
    local o = self.parent(parent, x, y)
    setmetatable(o, {__index = self})
    o._borderSet = borderset
    o:bordered(true)
    ---@cast o Border
    return o
end

---@param value? number
---@return number
function Border:width(value)
    checkArg(1, value, 'number', 'nil')
    
    return oldValue
end

---@param value? number
---@return number
function Border:height(value)
    checkArg(1, value, 'number', 'nil')
    
    return oldValue
end

function Border:draw()
    if (not self:visible()) then return end
    
    local defaultBuffer, newBuffer = self:_initBuffer()
    local x, y, width, height = self:absX(), self:absY(), self:width(), self:height()
    gpu.fill(x, y, width, height, " ")
    --sort widgets by z
    local unsorted = false
    for i, w in pairs(self._childs) do
        if (i > 1) then
            if (self._childs[i - 1]:z() > w:z()) then
                unsorted = true
                break
            end
        end
    end
    if (unsorted) then table.sort(self._childs, function(a, b) return a:z() < b:z() end) end

    --draw widgets
    for _, element in pairs(self._childs) do
        element:draw()
    end
    --restore buffer
    self:_restoreBuffer(defaultBuffer, newBuffer)
    return true
end

return Border
