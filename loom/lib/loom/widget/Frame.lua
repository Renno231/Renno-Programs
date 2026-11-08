local checkArg = require("loom.util").checkArg
local gpu = require("loom.gpu")
local Widget = require("loom.widget.Widget")
local event = require("event")
local computer = require("computer")
local run = require("loom.run")
local input = require("loom.input")

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
local Frame = require("loom.class")(Widget)

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
    setmetatable(o, self)
    ---@cast o Frame
    o._childs = {}
    local w, h = gpu.getViewport()
    o:size(w - o:x() + 1, h - o:y() + 1)
    o._lastTouch = {x = 0, y = 0, t = 0}
    o._weldCount = 0
    o._propagateFirst = false
    if (not parentFrame) then
        local function propagate(...) run.guard(o, (...), o.propagateEvent, o, ...) end
        o._listeners = {
            touch  = event.listen("touch", function(...) run.guard(o, "touch", o._touchHandler, o, ...) end),
            drag   = event.listen("drag", propagate),
            drop   = event.listen("drop", propagate),
            scroll = event.listen("scroll", propagate),
            walk   = event.listen("walk", propagate),
        }
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
    self:invokeCallback("childAdded", containerChild)
end

---Remove a child from the container. Return the removed child on success
---@generic T : Widget|Frame
---@param child T
---@return T? child
function Frame:removeChild(child)
    local childId = 0
    for i, v in ipairs(self._childs) do
        if (v == child) then childId = i break end
    end
    if (childId > 0) then
        self:invokeCallback("childRemoved", self._childs[childId])
        table.remove(self._childs, childId)
        return child
    end
end

function Frame:clearChildren()
    for _, element in ipairs(self._childs) do
        element:Destroy(true)
    end
    self:invokeCallback("clearedChildren")
    self._childs = {}
    return true
end

function Frame:propagateEvent(eName, screenAddress, x, y, ...)
    if (not self:enabled()) then return end
    self:_sort()
    
    for i = #(self._childs), 1, -1 do
        local w = self._childs[i]
        if w:visible() and w:checkCollision(x, y) then -- hidden widgets don't take signals
            local cSuccess 
            if (w:instanceOf(Frame)) then
                ---@cast w Frame
                --frame needs callback first, if not return true then propagate downward
                if w:propagateFirst() then
                    if (w:propagateEvent(eName, screenAddress, x, y, ...) == true) then
                        return true
                    elseif w:invokeCallback(eName, screenAddress, x, y, ...) == true then
                        return true
                    end
                else
                    if w:invokeCallback(eName, screenAddress, x, y, ...) == true then
                        return true
                    elseif (w:propagateEvent(eName, screenAddress, x, y, ...) == true) then
                        return true
                    end
                end
            else
                cSuccess = w:invokeCallback(eName, screenAddress, x, y, ...)
            end
            
            if cSuccess or (w:lockPropagationOnCallback() and w:_listens(eName)) then
                return true
            else
                return self:invokeCallback(eName, screenAddress, x, y, ...)
            end 
        end
    end
    return self:invokeCallback(eName, screenAddress, x, y, ...) 
end

function Frame:propagateFirst(value)
    checkArg(1, value, 'boolean', 'nil')
    local oldValue = self._propagateFirst
    if (value ~= nil) then self._propagateFirst = value end
    return oldValue
end

---@param value? number
---@return number
function Frame:doubleTouchDelay(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._doubleTouchDelay or 0.5
    if (value ~= nil) then self._doubleTouchDelay = value end
    return oldValue
end

function Frame:_drawnBounds(x,y,width,height)
    checkArg(1, x, 'number', 'nil')
    checkArg(1, y, 'number', 'nil')
    checkArg(1, width, 'number', 'nil')
    checkArg(1, height, 'number', 'nil')
    local oldValue = self._drawnBoundsValues
    if (x and y and width and height) then 
        self._drawnBoundsValues = self._drawnBoundsValues or {}
        self._drawnBoundsValues[1] = x -- = {x,y,width,height} 
        self._drawnBoundsValues[2] = y
        self._drawnBoundsValues[3] = width
        self._drawnBoundsValues[4] = height
    end
    if oldValue then
        return oldValue[1], oldValue[2], oldValue[3], oldValue[4]
    end
end

---Start drawing a root frame: draw into the root's own screen-sized buffer, kept between draws,
---and record the drawing calls. Frames inside a root draw straight into the root's buffer.
---@protected
---@return number? screenBuffer,number? buffer
function Frame:_initBuffer()
    if self:getParent() then return end
    local rwidth, rheight = gpu.getResolution()
    local buffer = self._buffer
    if buffer then
        local bwidth, bheight = gpu.getBufferSize(buffer)
        if bwidth ~= rwidth or bheight ~= rheight then
            if bwidth then gpu.freeBuffer(buffer) end
            buffer = nil
        end
    end
    if not buffer then
        buffer = gpu.allocateBuffer(rwidth, rheight)
        self._buffer, self._bufferArea = buffer, rwidth * rheight
        self._lastDrawLog = nil -- a new buffer is drawn whole
    end
    local screenBuffer = gpu.getActiveBuffer()
    if buffer then
        gpu.setActiveBuffer(buffer)
        if not self:backgroundColor() then --start from what is on screen, for transparency
            local x, y = self:absX(), self:absY()
            gpu.bitblt(buffer, x, y, self:width(), self:height(), screenBuffer, bitBltFix and y or x, bitBltFix and x or y)
        end
    end
    gpu.record(self)
    return screenBuffer, buffer
end

---Copy w x h at x, y of `buffer` to the same place on `screenBuffer`.
---OpenComputers charges a copy to the screen by the size of the buffer it comes from, and a
---screen-sized one costs more than a tier-3 computer's call budget for a tick, so every such copy
---waits a tick. Copies between buffers are free, so a small part goes through a buffer its own size.
---@private
function Frame:_blit(screenBuffer, buffer, x, y, w, h)
    local from, fx, fy = buffer, x, y
    if w * h * 2 <= self._bufferArea then -- costs at most two thirds of a tier-3 tick's budget
        local stage = self._stage
        if stage and (self._stageW ~= w or self._stageH ~= h) then gpu.freeBuffer(stage) stage = nil end
        if not stage then
            stage = gpu.allocateBuffer(w, h)
            self._stage, self._stageW, self._stageH = stage, w, h
        end
        if stage then
            gpu.bitblt(stage, 1, 1, w, h, buffer, bitBltFix and y or x, bitBltFix and x or y)
            from, fx, fy = stage, 1, 1
        end
    end
    gpu.bitblt(screenBuffer, x, y, w, h, from, bitBltFix and fy or fx, bitBltFix and fx or fy)
end

---Finish drawing a root frame: copy what changed in its buffer to the screen.
---@param screenBuffer? number
---@param buffer? number
function Frame:_restoreBuffer(screenBuffer, buffer)
    if not screenBuffer then return end
    local changed, x1, y1, x2, y2 = gpu.finish(self)
    if buffer then
        if changed then
            local x, y = self:absX(), self:absY()
            local r, b = x + self:width() - 1, y + self:height() - 1
            if x1 then x, y, r, b = math.max(x, x1), math.max(y, y1), math.min(r, x2), math.min(b, y2) end
            if x <= r and y <= b then self:_blit(screenBuffer, buffer, x, y, r - x + 1, b - y + 1) end
        end
        gpu.setActiveBuffer(screenBuffer)
    end
end

local function byZ(a, b) return a:z() < b:z() end

function Frame:_sort()
    local unsorted = false
    for i, w in pairs(self._childs) do
        if i> 1 and (self._childs[i - 1]:z() > w:z()) then
            unsorted = true
            break
        end
    end
    if (unsorted) then table.sort(self._childs, byZ) end
end

---Draw the widgets in the container
function Frame:draw()
    if self._layout and not self:getParent() then -- a root frame lays out against the screen
        local vw, vh = gpu.getViewport()
        self:_applyLayout(vw, vh, 0)
    end
    local x, y, width, height = self:absX(), self:absY(), self:width(), self:height()
    if (not self:visible()) or x==nil or y == nil or width == nil or height == nil then return end
    local screenBuffer, buffer = self:_initBuffer()

    --clean background
    local newBG = self:backgroundColor()
    if (newBG) then
        local oldBG = gpu.getBackground()
        gpu.setBackground(newBG)
        self:_gpufill(x, y, width, height, " ", true)
        gpu.setBackground(oldBG)
    else
        self:_gpufill(x, y, width, height, " ", true)
    end
    if not self._childs or #self._childs == 0 then
        local drawn = self.drawBorder and self:drawBorder() or false
        self:_restoreBuffer(screenBuffer, buffer)
        return drawn
    end
        
    --sort widgets by z
    self:_sort()
    local isRoot = self:getParent() == nil
    if isRoot then self:_animate() end
    local inset = self:bordered() and 1 or 0
    --draw widgets
    local hasWelds = self._weldCount > 0
    local animateOrWeld = hasWelds and "_calculateWeld" or "_animate"
    if hasWelds then
        for _, element in pairs(self._childs) do
            element:_animate()
        end
    end
    local focusedChild
    for _, element in pairs(self._childs) do --could (technically *should*) have error handling here
        if element._layout then element:_applyLayout(width, height, inset) end
        element[animateOrWeld](element)
        local bg, fg = gpu.getBackground(), gpu.getForeground()
        local noDrawError, drawReturn = xpcall(element.draw, debug.traceback, element)
        if not noDrawError then
            gpu.setBackground(bg)
            gpu.setForeground(fg)
            if not run.error(element, tostring(drawReturn), "draw") then element:_drawError(drawReturn) end
        end

        if noDrawError and drawReturn==true and element.drawBorder and not element._borderoverride then 
            element:drawBorder() 
        end
        if noDrawError and element:focusable() and element:visible() and element:width() > 0 and element:height() > 0 then
            input.shown(element)
            if input.focused() == element then focusedChild = element end
        end
    end
    if focusedChild then focusedChild:_drawFocus() end -- after the children, so none covers it
    
    if self.drawBorder and not self._borderoverride then self:drawBorder() end
    --might need to call self:drawBorder() like for the elements ^
    self:_restoreBuffer(screenBuffer, buffer)
    return true
end

function Frame:Destroy(force)
    if self._buffer then gpu.freeBuffer(self._buffer) end
    if self._stage then gpu.freeBuffer(self._stage) end
    return Widget.Destroy(self, force)
end

---Should the fix for bitBlt be used. Only apply to old OC versions.
Frame._bitBltFix = bitBltFix

--frame :Destroy should be quite aggressive I think, or at least be optionally aggressive in the sense that it destroys all of the child objects too instead of just unlinking them
return Frame
