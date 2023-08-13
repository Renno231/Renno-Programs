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

function Widget:defaultCallback()
end

---@param parent Frame
---@param x number
---@param y number
---@return Widget
---@overload fun(self:Widget,parent:Frame,position:Position):Widget
function Widget:new(parent, x, y)
    local o = self.parent()
    setmetatable(o, {__index = self})
    checkArg(1, parent, 'table', 'nil')
    checkArg(2, x, 'table', 'number')
    checkArg(3, y, 'number', 'nil')
    if (type(x) == 'number') then
        checkArg(3, y, 'number')
    else
        checkArg(3, y, 'nil')
    end
    ---@cast o Widget
    o._parentFrame = parent
    o._position = {x = 1, y = 1}
    o._size = {width = 1, height = 1}
    o:position(x, y)
    if (parent) then parent:addChild(o) end
    return o
end

function Widget:getParent() return self._parentFrame end

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
    if (x) then self._position.x = x end
    return oldX
end

---Set the y position. Return the old y position or the current one if no y is provided
---@param y? number
---@return number
function Widget:y(y)
    checkArg(1, y, 'number', 'nil')
    local oldY = self._position.y
    if (y) then self._position.y = y end
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
        return self._parentFrame:absX() + self:x() - 1
    else
        return self:x()
    end
end

---Get the absolute y position on screen.
---@return number
function Widget:absY()
    if (self._parentFrame) then
        return self._parentFrame:absY() + self:y() - 1
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
    if (value) then self._z = value end
    return oldValue
end

---Set the width. Return the old width or the current one if no width is provided
---@param width? number
---@return number
function Widget:width(width)
    checkArg(1, width, 'number', 'nil')
    local oldValue = self._size.width
    if (width) then self._size.width = width end
    return oldValue
end

---Set the height. Return the old height or the current one if no height is provided
---@param height? number
---@return number
function Widget:height(height)
    checkArg(1, height, 'number', 'nil')
    local oldValue = self._size.height
    if (height) then self._size.height = height end
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
    end
    if (oldVal == nil) then oldVal = true end
    return oldVal
end

---A set of characters used to draw the border.
---@param value? string
---@return string
function Widget:borderSet(value)
    checkArg(1, value, 'string', 'nil')
    local oldValue = self._borderSet
    if (value ~= nil) then self._borderSet = value end
    return oldValue
end

function Widget:bordered(value)
    checkArg(1, value, 'boolean', 'nil')
    local oldValue = self._bordered
    if (value ~= nil) then self._bordered = value end
    return oldValue
end

function Widget:drawBorder()
    if not self:bordered() or not self:borderSet() then return end
    local x, y, width, height = self:absX(), self:absY(), self:width(), self:height()
    local newBG = self:backgroundColor() 
    if newBG then
        local oldBG = gpu.getBackground()
        gpu.setBackground(newBG --[[@as number]])
        local borderSet = self:borderSet()
        if borderSet then
            local oldFG = self._foregroundColor and gpu.getForeground()
            if oldFG then gpu.setForeground(self._foregroundColor) end
            local unicode = require("unicode")
            local setLength = unicode.len(borderSet)
            if setLength > 3 then
                gpu.set(x, y, unicode.sub(borderSet, 1, 1))                                         --topleft
                gpu.set(x + width - 1, y, unicode.sub(borderSet, 2, 2))                             --topright
                gpu.set(x, y + height - 1, unicode.sub(borderSet, 3, 3))                            --bottomleft
                gpu.set(x + width - 1, y + height - 1, unicode.sub(borderSet, 4, 4))                --bottomright
                if setLength > 4 then
                    gpu.fill(x + 1, y, width - 2, 1, unicode.sub(borderSet, 5, 5))                  --top
                    if setLength == 6 then
                        gpu.fill(x + 1, y + height - 1, width - 2, 1, unicode.sub(borderSet, 5, 5)) --bottom
                        gpu.fill(x, y + 1, 1, height - 2, unicode.sub(borderSet, 6, 6))             --left
                        gpu.fill(x + width - 1, y + 1, 1, height - 2, unicode.sub(borderSet, 6, 6)) -- right
                    elseif setLength == 8 then
                        gpu.fill(x + 1, y + height - 1, width - 2, 1, unicode.sub(borderSet, 6, 6)) --bottom
                        gpu.fill(x, y + 1, 1, height - 2, unicode.sub(borderSet, 7, 7))             --left
                        gpu.fill(x + width - 1, y + 1, 1, height - 2, unicode.sub(borderSet, 8, 8)) -- right
                    end
                end
            end
            if oldFG then gpu.setForeground(oldFG) end
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
---```
---@param callback? function
---@param ...? any
---@return function,any ...
function Widget:callback(callback, ...)
    checkArg(1, callback, 'function', 'nil')
    local oldCallback = self._callback or self.defaultCallback
    local oldArgs = self._callbackArgs or {}
    if (callback) then
        self._callback = callback
    end
    if (...) then self._callbackArgs = table.pack(...) end
    return oldCallback, table.unpack(oldArgs)
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
    if (x < self:absX()) then return false end
    if (x > self:absX() + self:width() - 1) then return false end
    if (y < self:absY()) then return false end
    if (y > self:absY() + self:height() - 1) then return false end
    return true
end

---Draw the widgets in the container
function Widget:draw()
    if (not self:visible()) then return end
    return true
end

--size tween (linear)
function Widget:tweenSize(width, height, speed)
    checkArg(1, width, 'number', 'nil')
    checkArg(1, height, 'number', 'nil')
    checkArg(1, speed, 'number', 'nil')
    local goalWidth, goalHeight
    if self._tweenSize then
        goalWidth, goalHeight = self._tweenSize.goal.width, self._tweenSize.goal.height
    end
    if width and height then
        self._tweenSize = {speed = math.min(10, math.max(math.floor(speed or 1), 1)), step = 1, goal = {width = width, height = height}, original = {width = self:width(), height = self:height()}}
    end
    return goalWidth, goalHeight
end

--position tween (linear)
function Widget:tweenPosition(x, y, speed) --allow cancellation
    checkArg(1, x, 'number', 'nil')
    checkArg(1, y, 'number', 'nil')
    checkArg(1, speed, 'number', 'nil')
    local goalX, goalY
    if self._tweenPos then
        goalX, goalY = self._tweenPos.goal.x, self._tweenPos.goal.y
    end
    if x and y then
        self._tweenPos = {speed = math.min(10, math.max(math.floor(speed or 1), 1)), step = 1, goal = {x = x, y = y}, original = {x = self:x(), y = self:y()}} --maybe need to round if they are decimals
    end
    return goalX, goalY
end

function Widget:_tweenStep()
    if not self:enabled() or not self:visible() then return end
    --could add looping and total iterations, the ability to replay and the ability to pause
    --could also add bezier lerps
    if self._tweenPos then
        --require("component").ocelot.log('got tweenPos table')
        local ox, oy = self._tweenPos.original.x, self._tweenPos.original.y
        local nx, ny = self._tweenPos.goal.x, self._tweenPos.goal.y --new
        local targetStep = 10
        if self._tweenPos.step > targetStep then
            self._tweenPos = nil
            --could push a psuedo tweenPosFinished event here
        else
            local speed = self._tweenPos.speed / 10
            self:position(math.floor(ox + (nx - ox) * speed + 0.5), math.floor(oy + (ny - oy) * speed + 0.5 ) )
            self._tweenPos.step = self._tweenPos.step + 1
        end
    end
    if self._tweenSize then
        local owidth, oheight = self._tweenSize.original.width, self._tweenSize.original.height
        local nwidth, nheight = self._tweenSize.goal.width, self._tweenSize.goal.height
    
        local targetStep = 10
        if self._tweenSize.step > targetStep then
            self._tweenSize = nil
            self:size(nwidth, nheight) -- Set the final size to ensure accuracy, might not be necessary
            --could push a psuedo tweenSizeFinished event here
        else
            local t = self._tweenSize.step / targetStep
            self:size(math.floor(owidth + (nwidth - owidth) * t + 0.5), math.floor(oheight + (nheight - oheight) * t + 0.5))

            self._tweenSize.step = self._tweenSize.step + 1
        end
    end
end

function Widget:Destroy() --unparent and then .. ? 

end

Widget.Borders = {}
Widget.Borders.DOUBLE_LINE      = "╔╗╚╝═║"
Widget.Borders.SIMPLE_LINE      = "┌┐└┘─│"
Widget.Borders.BOLD_SIMPLE_LINE = "┏┓┗┛━┃"
Widget.Borders.THICK_EDGE_LINE  = "▛▜▙▟"..unicode.char(0x1fb83).."▄▌▐"
Widget.Borders.THINNER_EDGE_LINE= unicode.char(0x1fb15)..unicode.char(0x1fb28)..unicode.char(0x1fb32)..unicode.char(0x1fb37)..unicode.char(0x1fb02)..unicode.char(0x1fb2d).."▌▐"


return Widget