local gpu = require("component").gpu
local Widget = require("yawl-e.widget.Widget")
local unicode = require("unicode")
local keyboard = require('keyboard')
local wrap = require("yawl-e.util").wrap

local OutputQueue = require("libClass2")(Widget)

function OutputQueue:new(parent, x, y, width, height, backgroundColor)
    checkArg(1, parent, 'table')
    checkArg(2, x, 'number')
    checkArg(3, y, 'number')
    checkArg(4, width, 'number')
    checkArg(5, height, 'number')
    checkArg(6, backgroundColor, 'number')
    local o = self.parent(parent, x, y)
    setmetatable(o, {__index = self})
    o._list = {}
    o._shown = {} --used for selection
    o._selection = {} --for multi selection, selection[index] = index in _list
    o._scrollindex = 0
    ---@cast o SortedList
    o:size(width, height)
    o:backgroundColor(backgroundColor or 0)
    return o
end

function OutputQueue:queueMaxSize(value)
    checkArg(1, value, "number", 'nil')
    local oldValue = self._maxQueueSize
    if value then
        self._maxQueueSize = value
        self:invokeCallback("queueMaxSizeChanged", oldValue, value)
    end
    return oldValue
end

function OutputQueue:push(value)
    value = tostring(value)
    local max = self:queueMaxSize()
    -- require"component".ocelot.log(table.concat(wrap(value, self:width()), ", "))
    local toReturn
    local prefix = self:pushPrefix()
    local modifier = self:pushModifier()
    if prefix then 
        local succ, returned = pcall(prefix, self, value)
        if succ then 
            value = returned
        end
    end
    for i, str in ipairs(wrap(value, self:width())) do
        local toInsert = str
        if modifier then
            local succ, returned = pcall(modifier, self, #self._list, i, str)
            if succ and returned then toInsert = returned end
            if not succ then toInsert = "(mod func error) "..toInsert end 
        end
        table.insert(self._list, toInsert )
        self:invokeCallback("valueAdded", #self._list, toInsert)
        if max and #self._list > max then  
            toReturn = toReturn or {}
            table.insert(toReturn, self:pop())
        end
    end
    return toReturn
end

function OutputQueue:pushPrefix(prefixfunc) -- function (self, valueIndex, wrappedIndex, str)
    checkArg(1, prefixfunc, "function", 'boolean', 'nil')
    local oldValue = self._pushPrefixfunc
    if type(prefixfunc) == 'function' then
        self._pushPrefixfunc = prefixfunc
    end
    if prefixfunc == false then
        self._pushPrefixfunc = nil
    end
    return oldValue
end

function OutputQueue:pushModifier(modifierfunc) -- function (self, valueIndex, wrappedIndex, str)
    checkArg(1, modifierfunc, "function", 'boolean', 'nil')
    local oldValue = self._pushModifierFunc
    if type(modifierfunc) == 'function' then
        self._pushModifierFunc = modifierfunc
    end
    if modifierfunc == false then
        self._pushModifierFunc = nil
    end
    return oldValue
end

function OutputQueue:pop(index)
    checkArg(1, index, "number", 'nil')
    if #self._list > 0 then
        local removed = table.remove(self._list, index or 1)
        self:invokeCallback("valueRemoved", index or 1, removed)
        return removed
    end
end

function OutputQueue:list(value)
    checkArg(1, value, "table", 'nil')
    local oldValue = self._list
    if value then
        self._list = value
        self:invokeCallback("listChanged", oldValue, value)
    end
    return oldValue
end

function OutputQueue:getValue(index)
    checkArg(1, index, "number", 'nil')
    return self._list[index or 1] 
end

function OutputQueue:scroll(value, override)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._scrollindex or 0
    
    if (value ~= nil) then
        self._scrollindex = math.max(math.min(#self._list - self:height(), (override and 0 or self._scrollindex) + value), 0)
        if self._scrollindex ~= oldValue then self:invokeCallback("scrollYChanged", oldValue, self._scrollindex) end
    end
    return oldValue
end

function OutputQueue:defaultCallback(_, eventName, uuid, x, y, button, playerName)
    if eventName == "scroll" then
        local oldScroll = self:scroll(button)
        return oldScroll~=self:scroll()
    end
end

function OutputQueue:numbered(value)
    checkArg(1, value, 'boolean', 'nil')
    local oldValue = self._numbered or false
    if (value ~= nil) then self._numbered = value end
    return oldValue
end

function OutputQueue:draw()
    if (not self:visible()) then return end
    local isBordered = self:bordered()
    local x, y, width, height = self:absX() + (isBordered and 1 or 0), self:absY() + (isBordered and 1 or 0), self:width() + (isBordered and -2 or 0), self:height() + (isBordered and -2 or 0)
    if height == 0 or width == 0 then return end
    local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()
    local newBG, newFG = self:backgroundColor(), self:foregroundColor()
    if newBG then gpu.setBackground(newBG) end
    if newFG then gpu.setForeground(newFG) end
    self:_gpufill(x, y, width, height, " ", true) --overwrite the background
    local listSize = self._list and #self._list
    if listSize == 0 or listSize == nil then return end

    local scrollIndex = self:scroll()
    local isNumbered = self:numbered()
    
    local linePrefix = isNumbered and "%+"..tostring(tostring(height):len()).."s:%+"..tostring(tostring(listSize):len()).."s "
    local line = height
    for i = math.max(1, listSize - scrollIndex ), math.max(1, listSize-height-scrollIndex), -1 do
        self:_gpuset(x, y + height + scrollIndex - 1 - (listSize - i), (isNumbered and string.format(linePrefix, line, i) or "") .. tostring(self._list[i]))
        line = line - 1
    end

    gpu.setBackground(oldBG)
    gpu.setForeground(oldFG)
    return true
end

return OutputQueue