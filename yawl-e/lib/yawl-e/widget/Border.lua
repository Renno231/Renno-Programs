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
    checkArg(1, borderset, "string", 'nil')
    local o = self.parent(parent, x, y)
    setmetatable(o, {__index = self})
    o:borderSet(borderset)
    o:bordered(true)
    o:_borderOverride(true)
    ---@cast o Border
    return o
end
--[=[
function Border:draw()
    if (not self:visible()) then return end
    local x, y = self:absX(), self:absY()
    local defaultBuffer, newBuffer = self:_initBuffer()
    
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

    --calculate tweens accordingly
    local width, height = 2,2
    for _, element in pairs(self._childs) do
        element:_tweenStep()
        --calcualte the Border dimensions and whatnot here after tweenstep
        local distWidth = element:x() + element:width()
        local distHeight = element:y() + element:height()
        if distWidth > width then width = distWidth end
        if distHeight > height then height = distHeight end 
    end

    --clean background
    if (self:backgroundColor()) then
        local oldBG = gpu.getBackground()
        gpu.setBackground(self:backgroundColor() --[[@as number]])
        gpu.fill(x, y, width, height, " ")
        gpu.setBackground(oldBG)
    end
    --draw the children widgets after wiping background
    for _, element in pairs(self._childs) do
        if element:draw() and element.drawBorder and not element._borderoverride then element:drawBorder() end
    end
    --draw the border
    if self.drawBorder and not self._borderoverride and self:bordered() then self:drawBorder() end
    --restore buffer
    self:_restoreBuffer(defaultBuffer, newBuffer)
    return true
end]=]

return Border
