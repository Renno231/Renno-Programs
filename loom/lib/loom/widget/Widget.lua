local checkArg = require("loom.util").checkArg
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
local Widget = require("loom.class")()
local gpu = require("loom.gpu")
local unicode = require("unicode")
local event = require("event")
local component = require"component"
local computer = require("computer")
local run = require("loom.run")
local input = require("loom.input")

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
    local o = setmetatable({}, self)
    ---@cast o Widget
    o._parentFrame = parent
    o._position = {x = x, y = y, z = 0}
    o._size = {width = 1, height = 1}
    -- _welds (widgets welded to this one) and _listeners (event listener ids) are created on first use

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

local none = {}

function Widget:closeListeners()
    for _, id in pairs(self._listeners or none) do
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

---Run `handler(self, ...)` when `eventName` happens, with the event's data (for screen events:
---screenAddress, x, y, button, playerName). Several handlers can share an event; a handler that
---returns true stops the event there. Returns the handler, for `off`.
---@param eventName string
---@param handler function
---@return function
function Widget:on(eventName, handler)
    checkArg(1, eventName, 'string')
    checkArg(2, handler, 'function')
    local handlers = self._handlers
    if not handlers then handlers = {} self._handlers = handlers end
    local list = handlers[eventName]
    if not list then list = {} handlers[eventName] = list end
    list[#list + 1] = handler
    return handler
end

---Remove a handler added with `on`, or every handler for `eventName` if `handler` is nil.
---@param eventName string
---@param handler? function
function Widget:off(eventName, handler)
    checkArg(1, eventName, 'string')
    checkArg(2, handler, 'function', 'nil')
    local list = self._handlers and self._handlers[eventName]
    if not list then return end
    for i = #list, 1, -1 do
        if handler == nil or list[i] == handler then table.remove(list, i) end
    end
    if #list == 0 then self._handlers[eventName] = nil end
end

---Invoke the callback, then the `on` handlers. Returns true if any of them handled the event.
---@param eventName string
---@param ... any Signal data
function Widget:invokeCallback(eventName, ...)
    if (not self:enabled()) then return end
    local args = self._callbackArgs
    local handled = (self._callback or self.defaultCallback)(self, args and args[1], eventName, ...)
    local list = self._handlers and self._handlers[eventName]
    if list and not handled then
        for i = 1, #list do
            if list[i](self, ...) == true then return true end
        end
    end
    return handled
end

---True if a callback or handler is set for `eventName`; such widgets stop screen events from reaching widgets behind them.
---@package
function Widget:_listens(eventName)
    return (self._callback and self._callback ~= self.defaultCallback) or self.defaultCallback ~= Widget.defaultCallback
        or (self._handlers and self._handlers[eventName]) ~= nil
end

---Ask `loom.run` to redraw soon, after changing widgets outside an event (from a timer, say).
function Widget:invalidate() run.request(0) end

---Can this widget take keyboard focus? Buttons, switches, sliders, lists, dropdowns and text
---fields can by default; `focusable(true)` makes any widget focusable. A focused widget gets Enter
---and Space as a touch, so its touch callback runs.
---@param value? boolean
---@return boolean
function Widget:focusable(value)
    checkArg(1, value, 'boolean', 'nil')
    local old = self._focusable
    if old == nil then old = self._canFocus or false end
    if value ~= nil then self._focusable = value end
    return old
end

---Give this widget keyboard focus. `player`, if given, is the only player whose keys count.
---@param player? string
function Widget:focus(player) input.focus(self, player) end

---Take keyboard focus away from this widget.
function Widget:blur()
    if input.focused() == self then input.focus(nil) end
end

---@return boolean
function Widget:focused() return input.focused() == self end

---Handle a key while focused. Return true if the key was used; otherwise loom handles it
---(Tab, arrows, Enter/Space as a touch, then `loom.onKey`).
---@protected
function Widget:_key(char, code, ctrl, player) return false end

---Draw the focus marker: white brackets just outside the widget, on its parent's background, so
---the widget keeps its look. `[` `]` beside a one-row widget, `┌│└` `┐│┘` beside a taller one.
---When focus moves, the brackets slide over from the last widget (see `loom.focusGlide`).
---Frame calls this after drawing its children, so siblings don't cover it.
---@protected
function Widget:_drawFocus()
    local parent = self:getParent()
    if self:width() < 1 or self:height() < 1 or not parent then return end
    local x, y, w, h = input.markerBox(self, self:absX(), self:absY(), self:width(), self:height())
    local px, py, pw, ph = parent:absX(), parent:absY(), parent:width(), parent:height()
    if parent._drawnBounds then
        local dx, dy, dw, dh = parent:_drawnBounds()
        if dx then px, py, pw, ph = dx, dy, dw, dh end
    end
    local bg, p = parent:backgroundColor(), parent:getParent()
    while not bg and p do bg, p = p:backgroundColor(), p:getParent() end
    local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()
    gpu.setForeground(0xffffff)
    if bg then gpu.setBackground(bg) end
    local function put(cx, cy, char)
        if cx >= px and cx < px + pw and cy >= py and cy < py + ph then gpu.set(cx, cy, char) end
    end
    local left, right = x - 1, x + w
    for row = y, y + h - 1 do
        if h == 1 then
            put(left, row, "[") put(right, row, "]")
        elseif row == y then
            put(left, row, "┌") put(right, row, "┐")
        elseif row == y + h - 1 then
            put(left, row, "└") put(right, row, "┘")
        else
            put(left, row, "│") put(right, row, "│")
        end
    end
    gpu.setBackground(oldBG)
    gpu.setForeground(oldFG)
end

---Place and size this widget relative to its parent on every draw. Fields, in cells or as "N%" of the
---parent's inner size: `left`, `right`, `top`, `bottom`, `width`, `height`; and `center` = true, "x"
---or "y". `left` and `right` together set the width; one of them pins that edge. `false` removes it.
---```lua
---list:layout{left = 1, right = 1, top = 3, bottom = 2} -- fill the parent, with margins
---button:layout{right = 1, bottom = 0, width = 10}    -- bottom-right corner
---panel:layout{width = "50%", height = "50%", center = true}
---```
---@param spec? table|false
---@return table|false
function Widget:layout(spec)
    checkArg(1, spec, 'table', 'boolean', 'nil')
    local old = self._layout or false
    if spec == false then
        self._layout = nil
    elseif spec then
        local parsed = {}
        for key, value in pairs(spec) do
            if type(value) == "string" and value:sub(-1) == "%" then
                value = {tonumber(value:sub(1, -2)) / 100}
            end
            parsed[key] = value
        end
        self._layout = parsed
    end
    return old
end

local function cells(v, total)
    if type(v) == "table" then return math.floor(v[1] * total + 0.5) end
    return v
end

-- One axis of a layout: returns the new position and size, or nil to leave the position.
local function axis(lo, hi, size, total, center, current)
    lo, hi, size = cells(lo, total), cells(hi, total), cells(size, total)
    if lo and hi then return lo + 1, math.max(0, total - lo - hi) end
    size = size or current
    if lo then return lo + 1, size end
    if hi then return total - hi - size + 1, size end
    if center then return (total - size) // 2 + 1, size end
    return nil, size
end

---Apply the layout inside a `width` x `height` area (the parent's size).
---@package
function Widget:_applyLayout(width, height, inset)
    local l = self._layout
    local c = l.center
    local x, w = axis(l.left, l.right, l.width, width - 2 * inset, c == true or c == "x", self:width())
    local y, h = axis(l.top, l.bottom, l.height, height - 2 * inset, c == true or c == "y", self:height())
    if x then self:x(x + inset) end
    if y then self:y(y + inset) end
    self:size(w, h)
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
        if pwidth <= 0 or pheight <= 0 or x >= px + pwidth or y >= py + pheight or x + width <= px or y + height <= py then
            if isBoundingBox and self._drawnBounds then self:_drawnBounds(x, y, 0, 0) end -- nothing of it shows
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

---Show a draw error: a red box over the widget with the first line of the message.
---@package
function Widget:_drawError(message)
    local x, y, width, height = self:absX(), self:absY(), self:width(), self:height()
    local bg, fg = gpu.setBackground(0xcc0000), gpu.setForeground(0xffffff)
    self:_gpufill(x, y, width, height, " ")
    local text = tostring(message):match("^[^\n]*"):gsub("^/[^:]*/", "")
    for row = 0, height - 1 do
        local part = unicode.sub(text, row * width + 1, (row + 1) * width)
        if part == "" then break end
        self:_gpuset(x, y + row, part)
    end
    gpu.setBackground(bg)
    gpu.setForeground(fg)
end

---Draw the widgets in the container
function Widget:draw()
    if (not self:visible()) then return end
    return true
end

---Animate properties towards `to` over `seconds`: position, size, colours, or any numeric
---property the widget has (a ProgressBar's `value`, say). See loom/animation.lua for options:
---`easing`, `delay`, `repeats`, `yoyo`, `onDone`. Returns the animation (`:cancel()`, `:finish()`).
---```lua
---panel:animate({x = 10, backgroundColor = 0x003366}, 0.4, {easing = "outBack"})
---```
---@param to table
---@param seconds? number
---@param options? table
---@return Animation
function Widget:animate(to, seconds, options)
    checkArg(1, to, 'table')
    checkArg(2, seconds, 'number', 'nil')
    checkArg(3, options, 'table', 'nil')
    return require("loom.animation").start(self, to, seconds, options)
end

---Stop every animation on this widget, leaving it where it is (or at the end, if `finish`).
---@param finish? boolean
function Widget:stopAnimations(finish)
    local list = {table.unpack(self._anims or {})}
    for _, a in ipairs(list) do
        if finish then a:finish() else a:cancel() end
    end
    self._anims = nil
end

---Move to x, y over `seconds` (default 0.5). With no arguments, return the target while moving.
---@param x? number
---@param y? number
---@param seconds? number
---@param options? table
---@return number? x,number? y
function Widget:moveTo(x, y, seconds, options)
    checkArg(1, x, 'number', 'nil')
    checkArg(2, y, 'number', 'nil')
    local animation = self._anims and require("loom.animation")
    local oldX, oldY = animation and animation.target(self, "x"), animation and animation.target(self, "y")
    if x and y then self:animate({x = x, y = y}, seconds, options) end
    return oldX, oldY
end

---Resize to width, height over `seconds` (default 0.5). With no arguments, return the target while resizing.
---@param width? number
---@param height? number
---@param seconds? number
---@param options? table
---@return number? width,number? height
function Widget:resizeTo(width, height, seconds, options)
    checkArg(1, width, 'number', 'nil')
    checkArg(2, height, 'number', 'nil')
    local animation = self._anims and require("loom.animation")
    local oldW, oldH = animation and animation.target(self, "width"), animation and animation.target(self, "height")
    if width and height then self:animate({width = width, height = height}, seconds, options) end
    return oldW, oldH
end

---Old names: `speed` was a number of draws (at least 10); now a draw is taken as 1/20 s.
function Widget:tweenPosition(x, y, speed) return self:moveTo(x, y, speed and math.max(10, speed) / 20) end
function Widget:tweenSize(width, height, speed) return self:resizeTo(width, height, speed and math.max(10, speed) / 20) end

---Advance this widget's animations; called by the parent frame before each draw.
---@package
function Widget:_animate()
    if self._anims and self:enabled() and self:visible() then require("loom.animation").step(self) end
end

--todo: add weldAlignment (changes where the weld is applied, for now its top left corner)
-- might also need to disallow or break existing welds if theres ever a circular reference ?
function Widget:weld(weldedTo, x, y) --could make x and y into functions that return a number?
    checkArg(1, weldedTo, 'table', 'boolean', 'nil')
    checkArg(2, x, 'function', 'number', 'nil')
    checkArg(3, y, 'function', 'number', 'nil')
    local currentWeldedTo = self._weld and self._weld.weldedTo
    local oldVal = self._weld
    if type(weldedTo)=="table" and weldedTo.weld and x and y then
        if currentWeldedTo then
            if currentWeldedTo._parentFrame then
                currentWeldedTo._parentFrame._weldCount = currentWeldedTo._parentFrame._weldCount - 1
            end 
            currentWeldedTo._welds[self] = nil --break and old welds
        end
        self._weld = {weldedTo = weldedTo, x = x, y = y}
        weldedTo._welds = weldedTo._welds or {}
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
    for obj, _ in pairs (self._welds or none) do
        obj:weld(false) -- breaks any attached welds
    end
end

function Widget:reset()
    self:closeListeners()
    self:breakWelds()
    self._anims = nil
end

function Widget:Destroy(force) --unparent and then .. ? 
    if force == nil then force = true end
    input.forget(self)
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
