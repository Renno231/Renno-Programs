local gpu = require("component").gpu
local Widget = require("yawl-e.widget.Widget")
local event = require("event")
local computer = require("computer")

--=============================================================================
--test bitblt bug
local bitBltFix = false
local testBuffer1 = gpu.allocateBuffer(2, 2)
local testBuffer2 = gpu.allocateBuffer(2, 2)
gpu.setActiveBuffer(testBuffer1)
gpu.set(1, 2, 'X')
gpu.bitblt(testBuffer2, 1, 2, 1, 1, testBuffer1, 1, 2)
gpu.setActiveBuffer(testBuffer2)
if (gpu.get(1, 2) == 'X') then
    bitBltFix = false
else
    bitBltFix = true
end
gpu.setActiveBuffer(0)
gpu.freeBuffer(testBuffer1)
gpu.freeBuffer(testBuffer2)

--=============================================================================

---@class Frame:Widget
---@field parent Widget
---@field private _parentFrame? Frame Inherited from Widget, but made optional
---@field protected _childs table<number,Widget|Frame>
---@field private _listeners table
---@field private _lastTouch table
---@field private _doubleTouchDelay number
---@operator call:Frame
---@overload fun():Frame
---@overload fun(parent:Frame):Frame
---@overload fun(parent:Frame,x:number,y:number):Frame
local Frame = require("libClass2")(Widget)

---@param parentFrame Frame
---@param x number
---@param y number
---@return Frame
---@overload fun(self:Frame):Frame
---@overload fun(self:Frame,parentFrame:Frame):Frame
---@overload fun(self:Frame,parentFrame:Frame,position:Position):Frame
function Frame:new(parentFrame, x, y)
    checkArg(1, parentFrame, 'table', 'nil')
    checkArg(2, x, 'number', 'nil')
    checkArg(3, y, 'number', 'nil')
    if (not x) then
        checkArg(3, y, 'nil')
        x = 1
        y = 1
    end
    local o = self.parent(parentFrame, x, y)
    setmetatable(o, {__index = self})
    ---@cast o Frame
    o._childs = {}
    local w, h = gpu.getViewport()
    o:size(w - o:x() + 1, h - o:y() + 1)
    o._lastTouch = {x = 0, y = 0, t = 0}
    o._weldCount = 0
    if (not parentFrame) then
        o._listeners.touch =  event.listen("touch",  function(...) o:_touchHandler(...)  end)
        o._listeners.drag =   event.listen("drag",   function(...) o:propagateEvent(...) end)
        o._listeners.drop =   event.listen("drop",   function(...) o:propagateEvent(...) end)
        o._listeners.scroll = event.listen("scroll", function(...) o:propagateEvent(...) end)
        o._listeners.walk =   event.listen("walk",   function(...) o:propagateEvent(...) end)
    end
    return o
end

---@package
function Frame:_touchHandler(eName, screenAddress, x, y, ...)
    local cTime = computer.uptime()
    self:propagateEvent(eName, screenAddress, x, y, ...)
    if (x == self._lastTouch.x and y == self._lastTouch.y) then
        if ((cTime - self._lastTouch.t) < self:doubleTouchDelay()) then
            self:propagateEvent("double_touch", screenAddress, x, y, ...)
        end
    end
    self._lastTouch = {x = x, y = y, t = cTime}
end

---Add a widget container to the container
---@param containerChild Widget|Frame
function Frame:addChild(containerChild)
    table.insert(self._childs, containerChild)
end

---Remove a child from the container. Return the removed child on success
---@generic T : Widget|Frame
---@param child T
---@return T? child
function Frame:removeChild(child)
    local childId = 0
    for i, v in pairs(self._childs) do
        if (v == child) then childId = i end
    end
    if (childId > 0) then
        table.remove(self._childs, childId)
        return child
    end
end

function Frame:clearChildren()
    self._childs = {}
    return true
end

function Frame:propagateEvent(eName, screenAddress, x, y, ...)
    if (not self:enabled()) then return end
    table.sort(self._childs, function(a, b) return a:z() < b:z() end)
    for i = #(self._childs), 1, -1 do
        local w = self._childs[i]
        --TODO : find a new yeilding methods
        --os.sleep()
        if (w:checkCollision(x, y)) then
            if (w:instanceOf(Frame)) then
                ---@cast w Frame
                --frame needs callback first, if not return true then propagate downward
                if w:invokeCallback(eName, screenAddress, x, y, ...) == true then
                    return true
                elseif (w:propagateEvent(eName, screenAddress, x, y, ...) == true) then 
                    return true
                end
            else    
                w:invokeCallback(eName, screenAddress, x, y, ...)
            end
            return true
        end
    end
end

---@param value? number
---@return number
function Frame:doubleTouchDelay(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._doubleTouchDelay or 0.5
    if (value ~= nil) then self._doubleTouchDelay = value end
    return oldValue
end

---initialize a frame buffer
---@protected
---@return number defaultBuffer,number newBuffer
function Frame:_initBuffer()
    local x, y, width, height = self:absX(), self:absY(), self:width(), self:height()
    local rwidth, rheight = gpu.getResolution()
    local defaultBuffer = gpu.getActiveBuffer()
    local newBuffer, reason = gpu.allocateBuffer(rwidth, rheight)

    if newBuffer then
        defaultBuffer = gpu.setActiveBuffer(newBuffer) --means default buffer will always be the last one
    end

    if (newBuffer and newBuffer ~= defaultBuffer) then
        --copy the old buffer in the new buffer for transparancy effect
        gpu.bitblt(newBuffer, x, y, width, height, defaultBuffer, bitBltFix and y or x, bitBltFix and x or y)
    end
    return defaultBuffer, newBuffer
end

---copy to previous buffer and free buffer
---@param defaultBuffer number
---@param newBuffer number
function Frame:_restoreBuffer(defaultBuffer, newBuffer)
    local x, y, width, height = self:absX(), self:absY(), self:width(), self:height()
    if (newBuffer and newBuffer ~= defaultBuffer) then
        gpu.bitblt(defaultBuffer, x, y, width, height, newBuffer, bitBltFix and y or x, bitBltFix and x or y)
        gpu.setActiveBuffer(defaultBuffer)
        gpu.freeBuffer(newBuffer)
    end
end

function Frame:_sort()
    local unsorted = false
    for i, w in pairs(self._childs) do
        if i> 1 and (self._childs[i - 1]:z() > w:z()) then
            unsorted = true
            break
        end
    end
    if (unsorted) then table.sort(self._childs, function(a, b) return a:z() < b:z() end) end
end

---Draw the widgets in the container
function Frame:draw()
    local x, y, width, height = self:absX(), self:absY(), self:width(), self:height()
    if (not self:visible()) or x==nil or y == nil or width == nil or height == nil then return end
    --init frame buffer
    local defaultBuffer, newBuffer = self:_initBuffer()

    --clean background
    if (self:backgroundColor()) then
        local oldBG = gpu.getBackground()
        gpu.setBackground(self:backgroundColor() --[[@as number]])
        self:_gpufill(x, y, width, height, " ")
        gpu.setBackground(oldBG)
    end
    if not self._childs then return false end
    if #self._childs == 0 then return end
    --sort widgets by z
    self:_sort()
    local isRoot = self:getParent() == nil
    if isRoot then self:_tweenStep() end
    --draw widgets
    local hasWelds = self._weldCount > 0
    local tweenOrWeld = hasWelds and "_calculateWeld" or "_tweenStep"
    if hasWelds then
        for _, element in pairs(self._childs) do
            element:_tweenStep()
        end
    end
    for _, element in pairs(self._childs) do
        element[tweenOrWeld](element)
        if element:draw() and element.drawBorder and not element._borderoverride then 
            element:drawBorder() 
        end
    end
    if isRoot and self.drawBorder and not self._borderoverride then self:drawBorder() end
    --might need to call self:drawBorder() like for the elements ^
    --restore buffer
    self:_restoreBuffer(defaultBuffer, newBuffer)
    return true
end

---Should the fix for bitBlt be used. Only apply to old OC versions.
Frame._bitBltFix = bitBltFix

--frame :Destroy should be quite aggressive I think, or at least be optionally aggressive in the sense that it destroys all of the child objects too instead of just unlinking them
return Frame
