local gpu = require("component").gpu
local Widget = require("yawl-e.widget.Widget")
local unicode = require("unicode")
local keyboard = require('keyboard')

---@class SortedList:Widget
---@field private _size Size
---@operator call:SortedList
---@overload fun(parent:Frame,x:number,y:number,width:number,height:number,backgroundColor:number)
local SortedList = require("libClass2")(Widget)
---Create a new SortedList
---@param parent Frame
---@param x number
---@param y number
---@param width number
---@param height number
---@param backgroundColor number
---@return SortedList
function SortedList:new(parent, x, y, width, height, backgroundColor)
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
    o._showsErrors = false
    ---@cast o SortedList
    o:size(width, height)
    o:backgroundColor(backgroundColor or 0)
    return o
end

function SortedList:maximumSelectedValues(value)
    checkArg(1, value, 'number', 'boolean', 'nil')
    local oldValue = self._maximumSelection
    if type(value) == "number" then self._maximumSelection = value end
    if value == false then self._maximumSelection = nil end
    return oldValue
end

function SortedList:select(index, state) --getter/setter
    checkArg(1, index, 'number')
    checkArg(1, state, 'boolean', 'nil')
    local oldValue = self._selection[index]
    if state ~= nil then --needs work 
        local max = self:maximumSelectedValues()
        local totalSelected = max and #self:getSelection()
        if (max and totalSelected < max) or state == false or max == nil then
            if oldValue~=nil and oldValue ~= index then
                self:invokeCallback("selectionChanged", self:getSelection(), self._value)
            end
            self._selection[index] = state --select
        end
    end
    return oldValue
end

function SortedList:value(index, newval) --getter/setter, use delete to remove things
    checkArg(1, index, 'number')
    local oldValue = self._list[index]
    if newval ~= nil then --needs work 
        self._list[index] = newval --overwrite
        self:invokeCallback("valueChanged", oldValue, newval, index)
    end
    return oldValue
end

function SortedList:insert(value, index)
    checkArg(1, value, 'table', 'boolean', 'number', 'string')
    checkArg(1, index, 'number', 'nil')
    if type(value) == 'table' then
        for _,v in pairs (self._list) do
            if v == value then
                return false, 'table already inserted'
            end
        end
    end
    if type(index)=='number' then
        table.insert(self._list, index, value) 
        self:invokeCallback("valueAdded", index, value)
    else
        table.insert(self._list, value)
        self:invokeCallback("valueAdded", #self._list, value)
    end
    return true
end

function SortedList:delete(value) 
    --can be index or string or table, if its not a number then iterate through list and do a direct == comparison and use table.remove(self._list, i)
    checkArg(1, value, 'function', 'number', 'table', 'string', 'boolean')
    local valueType = type(value)
    if valueType == 'function' then --custom delete
        return value(self)
    elseif valueType == 'number' then --index
        if self._list[value] then
            local removed = table.remove(self._list, value)
            
            self:invokeCallback("valueRemoved", value, removed)
            return removed
        end
    else
        for i,v in ipairs (self._list) do
            if v == value then
                local removed = table.remove(self._list, value)
                self:invokeCallback("valueRemoved", value, removed)
                return removed
            end
        end
    end
    return false, 'no such value'
end

function SortedList:move(value, index) --shifts things around

end

function SortedList:sorter(sortfunc)
    checkArg(1, sortfunc, 'function', 'boolean', 'nil')
    local oldValue = self._sortfunc or false
    if (sortfunc ~= nil) then self._sortfunc = sortfunc end
    return oldValue
end

function SortedList:numbered(value)
    checkArg(1, value, 'boolean', 'nil')
    local oldValue = self._numbered or false
    if (value ~= nil) then self._numbered = value end
    return oldValue
end

function SortedList:filter(filterfunc)
    checkArg(1, filterfunc, 'function', 'boolean', 'nil')
    local oldValue = self._filterfunc or false
    if (filterfunc ~= nil) then self._filterfunc = filterfunc end
    return oldValue
end

function SortedList:filterBy(value) --sets the value that gets passed into filterFunc
    checkArg(1, value, 'string', 'number', 'nil', 'boolean')
    local oldValue = self._filter or false
    if (value ~= nil) then 
        self._filter = value
        if value == "" then 
            self._contextScroll = nil
            self._contextStart = nil
            self._contextEnd = nil
            self._highestContextIndex = nil --could cause problems in the event the list is dynamic with tables
        else 
            self._contextScroll = 0
        end
    end
    return oldValue
end

function SortedList:format(formatfunc) --for displaying values
    checkArg(1, formatfunc, 'function', 'boolean', 'nil')
    local oldValue = self._formatfunc or false
    if (formatfunc ~= nil) then self._formatfunc = formatfunc end
    return oldValue
end

function SortedList:list(newlist)
    checkArg(1, newlist, 'table', 'nil')
    local oldValue = self._list
    if (newlist ~= nil) then
        self._list = newlist
        self:invokeCallback("listChanged", oldValue, newlist)
    end
    return oldValue
end

function SortedList:clearList() --empty list
    self._list = {}
    self:invokeCallback("listCleared")
    return true
end

function SortedList:clearSelection() --empty list
    self._selection = {}
    self:invokeCallback("selectionCleared")
    return true
end

function SortedList:getSelection()
    local selected = {}
    for i,v in pairs (self._selection) do
        if v then table.insert(selected, i) end
    end
    return selected
end

function SortedList:mount(object)
    checkArg(1, object, 'table', 'nil', 'boolean')
    --check for duplicates first
    local oldValue = self._mount
    if type(object) == 'table' and object.text then --note: could potentially use something that isn't strictly text based, e.g., a toggle switch :value()
        self._mount = object
        self:invokeCallback("mounted", object)
    elseif object == false and self._mount then
        self._mount = nil
        self:invokeCallback("unmounted")
    end
    return oldValue
end

function SortedList:scroll(value, override) --not perfect, needs refinement for when filter has been applied, needs to differentiate between unfiltered and filtered
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._contextScroll or self._scrollindex or 0
    
    if (value ~= nil) then --and height <= shownheight then 
        if self._filter == "" or not self._filter then
            self._scrollindex = math.max(math.min(#self._list - self:height() + 1, (override and 0 or self._scrollindex) + value), 0)
        elseif #self._shown > 0 then --filterBy is set and there is something to visually scroll
            local currentListIndex = self._shown[1]
            if self._contextScroll == 0 then 
                self._contextStart = (currentListIndex or 1) - 1 
                self._contextScroll = self._contextStart 
            end
            
            if value == 1 then
                local nextListIndex = self._shown[2]
                if nextListIndex then
                    value = nextListIndex - currentListIndex
                end
            elseif value == -1 and currentListIndex>1 and (self._highestContextIndex == nil or self._highestContextIndex~=currentListIndex) then
                local nextListIndex, foundHigher = currentListIndex, false
                local filterFunc, filterValue = self:filter(), self:filterBy()
                repeat 
                    nextListIndex = nextListIndex - 1
                    local nextListValue = self._list[nextListIndex]
                    local succ, returned = pcall(filterFunc, filterValue, nextListValue)
                    foundHigher = (succ and returned~=nil and returned~=false ) or (not succ and self._showsErrors)
                until nextListIndex == 1 or foundHigher
                value = nextListIndex - currentListIndex
                if nextListIndex == 1 and not foundHigher then --searched and never found with current filter, gets wiped when new filterby value is passed
                    self._highestContextIndex = currentListIndex
                end
            end
            self._contextScroll = math.max(math.min((self._contextEnd <= self:height() and self._contextScroll or #self._list), self._contextScroll + value), self._contextStart)
        end
    end
    return oldValue
end

function SortedList:defaultCallback(_, eventName, uuid, x, y, button, playerName)
    if eventName == "touch" then
        local index = self._shown[y - self:absY() + 1 + (self:bordered() and -1 or 0)]
        if button == 0 then
            if keyboard.isControlDown() then
                self:select(index, not self:select(index))
                return
            else
                self:clearSelection()
            end
        end
        if index then
            self:select(index, button == 0) 
        end
        return true
    elseif eventName == "scroll" then
        if self:maximumSelectedValues() == 1 and keyboard.isControlDown() then
            local selected = self:getSelection()[1]
            if selected and self:value(selected-button)~=nil then
                self:select(selected, false)
                self:select(selected-button, true)
            end
        end
        local oldScroll = self:scroll(-button)
        return oldScroll~=self:scroll()
    end
end

---Draw the SortedList on screen
function SortedList:draw() --could make it check to see if its hitting the border of its parent and resize vertically
    if (not self:visible()) then return end
    local isBordered = self:bordered()
    local x, y, width, height = self:absX() + (isBordered and 1 or 0), self:absY() + (isBordered and 1 or 0), self:width() + (isBordered and -2 or 0), self:height() + (isBordered and -2 or 0)
    if height == 0 or width == 0 then return end
    local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()
    local newBG, newFG = self:backgroundColor(), self:foregroundColor()
    if newBG then gpu.setBackground(newBG) end
    if newFG then gpu.setForeground(newFG) end
    self:_gpufill(x, y, width, height, " ", true) --overwrite the background
    
    if #self._list == 0 then return end
    local sorterFunc = self:sorter()
    if sorterFunc then 
        local succ, err = pcall(table.sort, self._list, sorterFunc) 
        if not succ then
            self:_gpuset(x,y, unicode.sub(err, 1, width))
            return
        end
    end

    self._shown = {}
    local filterFunc, mounted, filterValue = self:filter(), self:mount()
    if mounted then
        local newFilterVal = mounted:text()
        if self:filterBy() ~= newFilterVal then self:filterBy(newFilterVal) end
        filterValue = newFilterVal
    else
        filterValue = self:filterBy()
    end
    if filterValue == "" then filterValue = nil end

    local i, scrollIndex, listValue = 1, self:scroll()
    for i, v in pairs (self._list) do
        if #self._shown > height then break end
        if type(i)=='number' and i>=scrollIndex then
            if filterFunc and filterValue then
                local succ, returned = pcall(filterFunc, filterValue, listValue)
                if succ then
                    if returned~=nil and returned~=false then
                        table.insert(self._shown, i)
                    end
                elseif self._showsErrors then
                    table.insert(self._shown, tostring(i).." (filter)"..returned)
                end
            else
                table.insert(self._shown, i)
            end
        end
    end
    
    local formatFunc, isNumbered = self:format(), self:numbered()
    local linePrefix = "%+"..tostring(tostring(#self._shown):len()).."s:%+"..tostring(tostring(#self._list):len()).."s "
    if filterValue then self._contextEnd = #self._shown end --for scrolling end detection
    
    for line, index in ipairs (self._shown) do
        if line > height then break end
        if type(index) == 'number' then
            local listValue = self._list[index]
            if formatFunc then 
                local succ, returned = pcall(formatFunc, listValue)
                listValue = (not succ and '(format)' or '') .. returned --should be fine
            end
            listValue = (isNumbered and string.format(linePrefix, line, index) or "") .. tostring(listValue):gsub("\n","; ")
            local isSelected = self._selection[index]
            if isSelected and newFG and newBG then gpu.setBackground(newFG) gpu.setForeground(newBG) end
            self:_gpuset(x, y+line-1, unicode.sub(listValue, 1, width) ) --do the formatting here
            if isSelected and newFG and newBG then gpu.setBackground(newBG) gpu.setForeground(newFG) end
        else
            local errVal = index:gsub("\n","; ")
            local failedIndex = errVal:match("%d+")
            errVal = unicode.sub(errVal, failedIndex:len()+2)
            self:_gpuset(x, y+line-1, unicode.sub( (isNumbered and string.format(linePrefix, line, failedIndex) or "") .. errVal, 1, width) )
        end
    end
    gpu.setBackground(oldBG)
    gpu.setForeground(oldFG)
    return true
end

function SortedList:Destroy()
    self:mount(false)
    self._list = nil
    self._shown = nil
    self._selection = nil
    Widget.Destroy(self)
end

return SortedList