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
    o._borderoverride = true
    o:autoFit(true, true)
    ---@cast o Border
    return o
end

---@param value? boolean
---@return boolean
function Border:autoFit(widthval, heightval)
    checkArg(1, widthval, 'boolean', 'nil')
    checkArg(1, heightval, 'boolean', 'nil')
    local oldValWidth, oldValHeight = self._autofitsWidth, self._autofitsHeight
    if (widthval ~= nil) then
        self._autofitsWidth = widthval
    end
    if (heightval ~= nil) then
        self._autofitsHeight = heightval
    end
    return oldValWidth, oldValHeight
end

function Border:draw()
    if (not self:visible()) then return end
    local x, y = self:absX(), self:absY()
    local defaultBuffer, newBuffer = self:_initBuffer()
    
    --sort widgets by z
    self:_sort()
    local isRoot = self:getParent() == nil
    if isRoot then self:_tweenStep() end
    --calculate tweens accordingly
    local width, height = self:size()
    local autoWidth, autoHeight = self:autoFit()
    if #self._childs>0 and autoWidth or autoHeight then
        width, height = autoWidth and 2 or width, autoHeight and 2 or height
        local hasWelds = self._weldCount > 0
        local tweenOrWeld = hasWelds and "_calculateWeld" or "_tweenStep"
        if hasWelds then
            for _, element in pairs(self._childs) do
                element:_tweenStep()
            end
        end
        for _, element in pairs(self._childs) do
            element[tweenOrWeld](element)
            --calcualte the Border dimensions and whatnot here after tweenstep
            if element:visible() then
                local distWidth = element:x() + element:width()
                local distHeight = element:y() + element:height()
                if autoWidth and distWidth > width then width = distWidth end
                if autoHeight and distHeight > height then height = distHeight end 
            end
        end
            
        if autoWidth then 
            self:width(width)
        end
        if autoHeight then
            self:height(height)
        end
    end
    --clean background
    if (self:backgroundColor()) then
        local oldBG = gpu.getBackground()
        gpu.setBackground(self:backgroundColor() --[[@as number]])
        self:_gpufill(x, y, width, height, " ", true)
        gpu.setBackground(oldBG)
    end
    --draw the children widgets after wiping background
    for _, element in pairs(self._childs) do
        if element:draw() and element.drawBorder and not element._borderoverride then element:drawBorder() end
    end
    --draw the border
    if self.drawBorder and self:bordered() then self:drawBorder() end
    --restore buffer
    self:_restoreBuffer(defaultBuffer, newBuffer)
    return true
end

return Border