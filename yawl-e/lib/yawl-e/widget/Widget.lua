---@class Widget:Object
---@field private _parentFrame Frame
---@field private _position Position
---@field private _size Size
---@field private _enabled boolean
---@field private _visible boolean
---@field private _z number
---@field private _callback function
---@field private _callbackArgs table
---@operator call:Widget
---@overload fun(parent:Frame,x:number,y:number):Widget
local Widget = require("libClass2")()
local gpu = require("component").gpu
local unicode = require("unicode")
local event = require("event")
local component = require"component"

function Widget:defaultCallback()
end

---@param parent Frame
---@param x number
---@param y number
---@return Widget
---@overload fun(self:Widget,parent:Frame,position:Position):Widget
function Widget:new(parent, x, y)
    checkArg(1, parent, 'table', 'nil')
    checkArg(2, x, 'table', 'number')
    checkArg(3, y, 'number', 'nil')
    if (type(x) == 'number') then
        checkArg(3, y, 'number')
    else
        checkArg(3, y, 'nil')
    end
    local o = self.parent()
    setmetatable(o, {__index = self})
    ---@cast o Widget
    o._parentFrame = parent
    o._position = {x = x, y = y, z = 0}
    o._size = {width = 1, height = 1}
    o._welds = {} --just for reference on doing cleanup
    o._listeners = {}
    
    if (parent) then parent:addChild(o) end
    return o
end

function Widget:getParent() return self._parentFrame end

function Widget:setParent(newparent, shouldClean) --kinda dangerous
    checkArg(1, newparent, 'table', 'nil') --how is this erroring when passing nil?
    checkArg(2, shouldClean, 'boolean', 'nil')
    
    local parent = self:getParent()
    shouldClean = shouldClean or shouldClean==nil
    if shouldClean and parent and parent.removeChild then 
        parent:removeChild(self) 
    end
    self._parentFrame = newparent
    if newparent~=nil and shouldClean then
        newparent:addChild(self)
    end
end
--[[
--adds a lot of complexity, may not be worth it
function Widget:reparent(newParent)
    local parent = self:getParent()
    if parent and newParent and newParent~=parent then 
        parent:removeChild(self) 
    end
    if newParent then
        self:setParent(newParent)
        newParent:addChild(self)
    end
end]]

---Set the Widget's position.
---@param x number
---@param y number
---@return number x, number y
---@overload fun(self:Widget):x:number,y:number
function Widget:position(x, y)
    checkArg(1, x, 'number', 'table', 'nil')
    checkArg(2, y, 'number', 'nil')
    local oldPosX, oldPosY = self:x(), self:y()
    if (type(x) == 'number') then
        self:x(x)
        self:y(y)
    elseif (type(x) == 'table') then
        checkArg(2, y, 'nil')
        self._position = x
    end
    return oldPosX, oldPosY
end

---Set the x position. Return the old x position or the current one if no x is provided
---@param x? number
---@return number
function Widget:x(x)
    checkArg(1, x, 'number', 'nil')
    local oldX = self._position.x
    if (x) then
        self._position.x = x
        if oldX ~= x then
            self:invokeCallback("xPosChanged", oldX, x)
        end
    end
    return oldX
end

---Set the y position. Return the old y position or the current one if no y is provided
---@param y? number
---@return number
function Widget:y(y)
    checkArg(1, y, 'number', 'nil')
    local oldY = self._position.y
    if (y) then
        self._position.y = y
        if oldY ~= y then
            self:invokeCallback("yPosChanged", oldY, y)
        end
    end
    return oldY
end

---Get the absolute Widget's position on screen.
---@return number x,number y
function Widget:absPosition()
    return self:absX(), self:absY()
end

---Get the absolute x position on screen.

---@return number
function Widget:absX()
    if (self._parentFrame) then
        return self._parentFrame:absX() + self:x() - 1 - (self._parentFrame.scrollX and math.floor(0.5+ self._parentFrame:scrollX()) or 0) 
    else
        return self:x()
    end
end

---Get the absolute y position on screen.
---@return number
function Widget:absY()
    if (self._parentFrame) then
        return self._parentFrame:absY() + self:y() - 1 - (self._parentFrame.scrollY and math.floor(0.5+ self._parentFrame:scrollY()) or 0) 
    else
        return self:y()
    end
end

---The z layer the widgets is on. Higher z will appear on front of others when drawn from a container like Frame
---@param value? number
---@return number
function Widget:z(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._z or 0
    if (value) then
        self._z = value
        if oldValue ~= value then
            self:invokeCallback("zPosChanged", oldValue, value)
        end
    end
    return oldValue
end

---Set the width. Return the old width or the current one if no width is provided
---@param width? number
---@return number
function Widget:width(width)
    checkArg(1, width, 'number', 'nil')
    local oldValue = self._size.width
    if (width) then
        self._size.width = width
        if oldValue ~= width then self:invokeCallback("widthChanged", oldValue, width) end
    end
    return oldValue
end

---Set the height. Return the old height or the current one if no height is provided
---@param height? number
---@return number
function Widget:height(height)
    checkArg(1, height, 'number', 'nil')
    local oldValue = self._size.height
    if (height) then
        self._size.height = height
        if oldValue ~= height then self:invokeCallback("heightChanged", oldValue, height) end
    end
    return oldValue
end

---Set the Widget's size.
---@param width number
---@param height number
---@return number x,number y
---@overload fun(self:Widget):x:number,y:number
function Widget:size(width, height)
    checkArg(1, width, 'number', 'nil')
    checkArg(2, height, 'number', 'nil')
    local oldW, oldH = self:width(), self:height()
    if (type(width) == 'number') then
        self:width(width)
        self:height(height)
    end
    return oldW, oldH
end

---@param value? number|false
---@return number
function Widget:backgroundColor(value)
    checkArg(1, value, 'number', 'boolean', 'nil')
    local oldValue = self._backgroundColor
    if (value == false) then
        self._backgroundColor = nil
    elseif (value ~= nil) then
        self._backgroundColor = value
    end
    return oldValue
end

---@param value? number
---@return number
function Widget:foregroundColor(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._foregroundColor
    if (value) then self._foregroundColor = value end
    return oldValue
end

---If value is provided, set if the container is visible and return the old value.\
---If value is not provided, return the current visible status
---@param value? boolean
---@return boolean
function Widget:visible(value)
    local oldVal = self._visible
    if (value ~= nil) then
        self._visible = value
        if oldVal ~= value then self:invokeCallback("visiblityChanged", oldVal, value) end
    end
    if (oldVal == nil) then
        oldVal = true
    end
    return oldVal
end

---A set of characters used to draw the border.
---@param value? string
---@return string
function Widget:borderSet(value)
    checkArg(1, value, 'string', 'nil')
    local oldValue = self._borderSet
    local setLen = value~=nil and unicode.len(value) or 0 
    if (value ~= nil) and (setLen == 4 or setLen == 6 or setLen == 8)  then self._borderSet = value end
    return oldValue
end

function Widget:bordered(value)
    checkArg(1, value, 'boolean', 'nil')
    local oldValue = self._bordered
    if (value ~= nil) then self._bordered = value end
    return oldValue
end

function Widget:borderUsesBackground(value)
    checkArg(1, value, 'boolean', 'nil')
    local oldValue = self._borderUsesBGColor
    if oldValue == nil then oldValue = true end
    if (value ~= nil) then self._borderUsesBGColor = value end
    return oldValue
end

function Widget:drawBorder()
    if not self:bordered() or not self:borderSet() then return end
    local x, y, width, height = self:absX(), self:absY(), self:width(), self:height()
    if width < 2 or height < 2 then return end
    local newBG = self:backgroundColor()
    if newBG then
        local oldBG = gpu.getBackground()
        gpu.setBackground(newBG --[[@as number]])
        local borderSet = self:borderSet()
        if borderSet then
            local oldFG = self._foregroundColor and gpu.getForeground()
            if oldFG then gpu.setForeground(self._foregroundColor) end
            local setLength = unicode.len(borderSet)
            if setLength > 3 then
                self:_gpuset(x, y, unicode.charAt(borderSet, 1))                                         --topleft
                self:_gpuset(x + width - 1, y, unicode.charAt(borderSet, 2))                             --topright
                self:_gpuset(x, y + height - 1, unicode.charAt(borderSet, 3))                            --bottomleft
                self:_gpuset(x + width - 1, y + height - 1, unicode.charAt(borderSet, 4))                --bottomright
                if setLength > 4 then
                    self:_gpufill(x + 1, y, width - 2, 1, unicode.charAt(borderSet, 5))                  --top
                    local isSix = setLength == 6
                    self:_gpufill(x + 1, y + height - 1, width - 2, 1, unicode.charAt(borderSet, isSix and 5 or 6)) --bottom
                    self:_gpufill(x, y + 1, 1, height - 2, unicode.charAt(borderSet, isSix and 6 or 7))             --left
                    self:_gpufill(x + width - 1, y + 1, 1, height - 2, unicode.charAt(borderSet, isSix and 6 or 8)) -- right
                end
            end
            if oldFG then gpu.setForeground(oldFG) end
            return true
        end
        gpu.setBackground(oldBG)
    end
end

---If value is provided, set if the container is enabled and return the old value.\
---If value is not provided, return the current enabled status
---@param value? boolean
---@return boolean
function Widget:enabled(value)
    local oldVal = self._enabled
    if (value ~= nil) then
        self._enabled = value
    end
    if (oldVal == nil) then oldVal = true end
    return oldVal
end

---Set or get the screen event callback method for this Widget.
---```lua
---function callback(self,[...,],...signalData) end

function Widget:closeListeners()
    for _, id in pairs(self._listeners) do
        if (type(id) == 'number') then event.cancel(id) end
    end
    return true
end

---```
---@param callback? function
---@param ...? any
---@return function,any ...
function Widget:callback(callback, ...)
    checkArg(1, callback, 'function', 'nil')
    local oldCallback = self._callback or self.defaultCallback
    local oldArgs = self._callbackArgs
    if (callback) then
        self._callback = callback
    end
    if (...) then self._callbackArgs = table.pack(...) end
    if oldArgs then
        return oldCallback, table.unpack(oldArgs)
    else
        return oldCallback
    end
end

---Invoke the callback method
---@param ... any Signal data
function Widget:invokeCallback(...)
    if (not self:enabled()) then return end
    local callback = self:callback()
    return callback(self, select(2, self:callback()), ...)
end

---Check if the x,y coordinates match the Widget
---@param x number
---@param y number
---@return boolean
function Widget:checkCollision(x, y)
    checkArg(1, x, 'number')
    checkArg(2, y, 'number')
    local abx,aby =  self:absPosition()
    local width,height = self:size()
    if (x < abx ) then return false end
    if (x > abx + width - 1) then return false end
    if (y < aby) then return false end
    if (y > aby + height - 1) then return false end
    return true
end

function Widget:lockPropagationOnCallback(value)
    checkArg(1, value, 'boolean', 'nil')
    local oldValue = self._shouldLockOnCallback
    if oldValue == nil then oldValue = true end
    if (value ~= nil) then self._shouldLockOnCallback = value end
    return oldValue
end
 
--not perfect yet
function Widget:_gpuset(x, y, str) --should maybe do some checkArg here
    if str == "" then return end
    local boundary = self:getParent()
    if not boundary then return end
    x, y = math.floor(x), math.floor(y)
    for i=1, 2 do
        if i == 2 then boundary = self end
        local px, py, pwidth, pheight = boundary:absX(), boundary:absY(), boundary:width(), boundary:height()
        if i == 1 and boundary._drawnBounds then
            local pdx, pdy, pdwidth, pdheight = boundary:_drawnBounds()
            if pdx then
                px, py, pwidth, pheight = pdx, pdy, pdwidth, pdheight
            end
        end
        if pwidth == 0 or pheight == 0 or x>px+pwidth-1 or y>=py+pheight or y<py then 
            return   --off screen 
        end
        local len = unicode.len(str)
        if x<px then --left bound
            str = unicode.sub(str, math.floor(math.abs(px-x))+1)
            x = px
            len = unicode.len(str)
        end
        if x+len > px+pwidth then --right bound
            str = unicode.sub(str, 1, math.floor(pwidth-(x-px)))
            len = unicode.len(str)
        end
        if x <= 0 and x>=-len+1 then --override undocumented native gpu edge case detection
            str = unicode.sub(str, math.floor(-x+2))
            x = 1
        end
        if str == "" then return end
    end
    if _G.snapshotLog == true then
        require("component").ocelot.log(tostring(x)..", ".. tostring(y)..":".. str)
    end
    gpu.set(x, y, str)
end

function Widget:_gpufill(x, y, width, height, char, isBoundingBox) --needs work
    x, y = math.floor(x), math.floor(y)
    local widgetParent = self:getParent()
    if widgetParent == nil and self._drawnBounds then
        self:_drawnBounds(x, y, width, height)
        if self:backgroundColor() then
            gpu.fill(x,y,width,height," ")
        end
        return
    elseif widgetParent == nil or char == nil or char == "" then
        return
    end
    
    local boundary = widgetParent
    for i=1, 2 do
        if i == 2 then
            boundary = self 
        end
        local px, py, pwidth, pheight = boundary:absX(), boundary:absY(), boundary:width(), boundary:height() 
        if i == 1 and boundary._drawnBounds then
            local pdx, pdy, pdwidth, pdheight = boundary:_drawnBounds()
            if pdx then
                px, py, pwidth, pheight = pdx, pdy, pdwidth, pdheight
            end
        end
        if pwidth == 0 or pheight == 0 or x>px+pwidth or y>py+pheight then 
            return 
        end
        if x<px then --off to the left
            width = width + (x-px)
            x=px
        end
        if y<py then --off to the top
            height = height + (y-py)
            y=py --needs adjustment?
        end
        if x+width > px+pwidth then
            width = pwidth-(x-px)
        end
        if y+height > py+pheight then
            height = pheight-(y-py)
        end
    end
    
    gpu.fill(x,y,width,height,char)
    if isBoundingBox and self._drawnBounds then
        self:_drawnBounds(x, y, width, height)
    end
    -- return
end

---Draw the widgets in the container
function Widget:draw()
    if (not self:visible()) then return end
    return true
end

--size tween (linear)
function Widget:tweenSize(width, height, speed)
    checkArg(1, width, 'number', 'nil')
    checkArg(2, height, 'number', 'nil')
    checkArg(3, speed, 'number', 'nil')
    local goalWidth, goalHeight
    if self._tweenSize then
        goalWidth, goalHeight = self._tweenSize.goal.width, self._tweenSize.goal.height
    end
    if width and height then
        self._tweenSize = {speed = math.max(10, math.max(math.floor(speed or 1), 1)), step = 1, goal = {width = width, height = height}, original = {width = self:width(), height = self:height()}}
    end
    return goalWidth, goalHeight
end

--position tween (linear)
function Widget:tweenPosition(x, y, speed) --allow cancellation
    checkArg(1, x, 'number', 'nil')
    checkArg(2, y, 'number', 'nil')
    checkArg(3, speed, 'number', 'nil')
    local goalX, goalY
    if self._tweenPos then
        goalX, goalY = self._tweenPos.goal.x, self._tweenPos.goal.y
    end
    if x and y then
        self._tweenPos = {speed = math.max(10, math.max(math.floor(speed or 1), 1)), step = 1, goal = {x = x, y = y}, original = {x = self:x(), y = self:y()}} --maybe need to round if they are decimals
    end
    return goalX, goalY
end

function Widget:_tweenStep()
    if not self:enabled() or not self:visible() then return end
    --could add looping and total iterations, the ability to replay and the ability to pause
    --could also add bezier lerps
    if self._tweenPos then
        local ox, oy = self._tweenPos.original.x, self._tweenPos.original.y
        local nx, ny = self._tweenPos.goal.x, self._tweenPos.goal.y --new
        local targetStep = self._tweenPos.speed
        if self._tweenPos.step > targetStep then --could check if its equal
            self._tweenPos = nil
            --could push a psuedo tweenPosFinished event here
        else
            local t = self._tweenPos.step / targetStep
            self:position(math.floor(ox + (nx - ox) * t + 0.5), math.floor(oy + (ny - oy) * t + 0.5 ) )
            self._tweenPos.step = self._tweenPos.step + 1
        end
    end
    if self._tweenSize then
        local owidth, oheight = self._tweenSize.original.width, self._tweenSize.original.height
        local nwidth, nheight = self._tweenSize.goal.width, self._tweenSize.goal.height
    
        local targetStep = self._tweenSize.speed
        if self._tweenSize.step > targetStep then
            self._tweenSize = nil
            --self:size(nwidth, nheight) -- Set the final size to ensure accuracy, might not be necessary
            --could push a psuedo tweenSizeFinished event here
        else
            local t = self._tweenSize.step / targetStep
            self:size(math.floor(owidth + (nwidth - owidth) * t + 0.5), math.floor(oheight + (nheight - oheight) * t + 0.5))

            self._tweenSize.step = self._tweenSize.step + 1
        end
    end
end

--todo: add weldAlignment (changes where the weld is applied, for now its top left corner)
-- might also need to disallow or break existing welds if theres ever a circular reference ?
function Widget:weld(weldedTo, x, y) --could make x and y into functions that return a number?
    checkArg(1, weldedTo, 'table', 'boolean', 'nil')
    checkArg(2, x, 'function', 'number', 'nil')
    checkArg(3, y, 'function', 'number', 'nil')
    local currentWeldedTo = self._weld and self._weld.weldedTo
    local oldVal = self._weld
    if type(weldedTo)=="table" and weldedTo._welds and x and y then
        if currentWeldedTo then
            if currentWeldedTo._parentFrame then
                currentWeldedTo._parentFrame._weldCount = currentWeldedTo._parentFrame._weldCount - 1
            end 
            currentWeldedTo._welds[self] = nil --break and old welds
        end
        self._weld = {weldedTo = weldedTo, x = x, y = y}
        weldedTo._welds[self] = true 
        if weldedTo._parentFrame then
            weldedTo._parentFrame._weldCount = weldedTo._parentFrame._weldCount + 1
        end 
    elseif weldedTo == false and self._weld then
        if currentWeldedTo._parentFrame then
            currentWeldedTo._parentFrame._weldCount = currentWeldedTo._parentFrame._weldCount - 1
        end 
        currentWeldedTo._welds[self] = nil -- breaks the reference
        self._weld = nil
        
        self:invokeCallback("weldBroken")
    end
    if oldVal then
        oldVal = {weldedTo = oldVal.weldedTo, x = oldVal.x, y = oldVal.y} --fresh table, don't want to pass the original since its by reference
    end
    return oldVal
end

function Widget:_calculateWeld()
    local weldData = self:weld()
    local weldedTo = weldData and weldData.weldedTo
    local weldedToParent = weldedTo and weldData.weldedTo.getParent and weldData.weldedTo:getParent()
    if not weldData or not weldedToParent then return end
    --if same parent, use :x() and :y(), if not, use absX() and absY() ?
    local uselocal = weldedToParent == self:getParent()
    local offx, offy = type(weldData.x) == "function" and (tonumber(weldData.x()) or 0) or weldData.x, type(weldData.y) == "function" and (tonumber(weldData.y()) or 0) or weldData.y
    self:position(offx + (uselocal and weldedTo:x() or weldedTo:absX()), offy + (uselocal and weldedTo:y() or weldedTo:absY())) 
    return true
end

function Widget:breakWelds()
    self:weld(false) -- breaks its own weld
    for obj, _ in pairs (self._welds) do
        obj:weld(false) -- breaks any attached welds
    end
end

function Widget:reset()
    self:closeListeners()
    self:breakWelds()
    self._tweenPos = nil
    self._tweenSize = nil
end

function Widget:Destroy(force) --unparent and then .. ? 
    if force == nil then force = true end
    self:closeListeners()
    self:enabled(false)
    -- if self.clearChildren then --should frames destroy any child objects when being destroyed?
    --     self:clearChildren()
    -- else
    if force and self._childs then
        local tempChilds = {} -- important since setParent(nil, nil) removes from the list in real time
        for _,v in ipairs (self._childs) do table.insert(tempChilds, v) end
        for _, element in ipairs(tempChilds) do
            if element.Destroy then
                local succ, err 
                if element._debug then
                    succ, err = xpcall(function() element:Destroy(force) end, debug.traceback)
                else
                    succ, err = pcall(element.Destroy, element, force) -- end, debug.traceback) --, element, force)
                end
                if not succ and err and component.isAvailable("ocelot") then
                    component.ocelot.log(err .. " DEBUG: " .. tostring(element._debug))
                end
            end
        end
        self._childs = {}
    end
    
    self:breakWelds()
    self:setParent(nil, nil)
    for i, v in pairs (self) do --hmm..
        --if type(v) == "table" and v.Destroy then v:Destroy() end
        rawset(self,i,nil) --self[i] = nil
    end
    setmetatable(self, {}) --should be fine
end

Widget.Borders = {}
Widget.Borders.DOUBLE_LINE      = "╔╗╚╝═║"
Widget.Borders.SIMPLE_LINE      = "┌┐└┘─│"
Widget.Borders.BOLD_SIMPLE_LINE = "┏┓┗┛━┃"
Widget.Borders.THICK_EDGE_LINE  = "▛▜▙▟"..unicode.char(0x1fb83).."▄▌▐"
Widget.Borders.THINNER_EDGE_LINE= unicode.char(0x1fb15)..unicode.char(0x1fb28)..unicode.char(0x1fb32)..unicode.char(0x1fb37)..unicode.char(0x1fb02)..unicode.char(0x1fb2d).."▌▐"

return Widget
