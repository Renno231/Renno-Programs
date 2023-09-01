local SortedList = require("yawl-e.widget.SortedList")
local class = require('libClass2')
local unicode = require("unicode")
local gpu = require("component").gpu

local Widget = require("yawl-e.widget.Widget")
local DropdownList = class(Widget)

function DropdownList:new(parent, x, y, width, height, backgroundColor, listobj) --not designed to work inside of UILayout
    checkArg(1, parent, 'table')
    checkArg(2, x, 'number')
    checkArg(3, y, 'number')
    checkArg(4, width, 'number')
    checkArg(5, height, 'number')
    checkArg(6, backgroundColor, 'number')
    checkArg(6, listobj, 'table','nil')
    local o = self.parent(parent, x, y)
    setmetatable(o, {__index = self})
    o._dropped = false
    ---@cast o DropdownList
    o:list(listobj or SortedList(parent, x, y+height, width, 5, backgroundColor))
    o:list():foregroundColor(0xffffff)
    
    o:list():weld(o, 0, 1)
    o:width(width)
    o:drop(false)
    o:size(width, height)
    o:backgroundColor(backgroundColor or 0)
    --do o._list custom touch based callback
    return o
end

function DropdownList:value(val) --number index in list or nil
    --hmm, list._list[list:getSelection()[1]]
end

function DropdownList:list(newlist) -- e.g., dropdown:list():sorter(function(...) end)
    checkArg(1, newlist, 'table', 'nil')
    local oldValue = self._list
    if newlist ~= nil and newlist.Class == "SortedList" then 
        self._list = newlist
        if oldValue == nil or newlist~=oldValue then
            --custom callback
            local dropdown = self
            self._list:callback(function(self, _, eventName, uuid, x, y, button, playerName) 
                if eventName == "touch" then
                    local index = self._shown[y - self:absY() + 1 + (self:bordered() and -1 or 0)]
                    if index then
                        self:clearSelection()
                        self:select(index, button == 0)
                        dropdown:toggle()
                    end
                    return true
                elseif eventName == "scroll" then
                    self:scroll(-button)
                    return true
                end
            end)
        end
    end
    return oldValue
end

function DropdownList:drop(value) --boolean or nil
    checkArg(1, value, 'boolean', 'nil')
    local oldValue = self._isDropped
    if self._list and value~=nil then
        self._isDropped = value
        self._list[self:animatedDrop() and "tweenSize" or "size"](self._list, self:width(), value and (self:listHeight() or #self._list._list) or 0)
    end
    return oldValue
end

function DropdownList:toggle()
    return self:drop(not self:drop())
end

function DropdownList:height(height)
    checkArg(1, height, 'number', 'nil')
    local oldValue = self._size.height
    if (height) then self._size.height = math.min(height, 1) end
    return oldValue
end
--todo: maybe add unenforced option for list object
function DropdownList:listHeight(value) --to enforce size when dropped
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._listHeight
    if (value ~= nil) then self._listHeight = value end
    return oldValue
end

function DropdownList:animatedDrop(value) -- boolean or nil
    --tell the :draw() to lerp the list instead
    checkArg(1, value, 'boolean', 'nil')
    local oldValue = self._animatedDrop
    if (value ~= nil) then self._animatedDrop = value end
    return oldValue
end

function DropdownList:defaultCallback(_, eventName, uuid, x, y, button, playerName) --idk yet, need to make a custom callback for the internal list so it properly triggers the DropdownList object
    if eventName == "touch" then
        if button == 1 and self:list() then
            self:list():clearSelection()
        else
            self:toggle()
        end
        return true
        --maybe add one for scroll that scrolls the list selection up/down by 1
    end
end

function DropdownList:charSet(value) --optional characters for the non-dropped and dropped states that prefix the shown value
    -- + and - for undropped and dropped?
    checkArg(1, value, 'string', 'nil')
    local oldValue = self._charSet
    if (value ~= nil) then self._charSet = unicode.sub(value, 1, 2) end
    return oldValue
end

function DropdownList:draw()
    --if self._list has a format function, use it on the selected value
    --list height used is the min of current height and given height
    if (not self:visible()) then return end
    local x, y, width, height = self:absX(), self:absY(), self:width(), self:height()
    if height == 0 or width == 0 then return end
    local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()
    local newBG, newFG = self:backgroundColor(), self:foregroundColor()
    if newBG then gpu.setBackground(newBG) end
    if newFG then gpu.setForeground(newFG) end
    self:_gpufill(x, y, width, height, " ") --overwrite the background
    local list = self._list
    if not list then return end
    list:width(width)
    local listValue = tostring(list._list[list:getSelection()[1]] or "")
    if not listValue then return end
    local formatFunc = list:format()
    if formatFunc then
        local succ, returned = pcall(formatFunc, listValue)
        listValue = (not succ and '(format)' or '') .. returned --should be fine
    end
    listValue = listValue:gsub("\n","; ")
    --append charSet to front of listValue
    local charset = self:charSet()
    if charset then
        listValue = (unicode.charAt(charset, self:drop() and 2 or 1)) .. " " .. listValue
    end
    self:_gpuset(x, y, unicode.sub(listValue, 1, width) ) --do the formatting here

    gpu.setBackground(oldBG)
    gpu.setForeground(oldFG)
    return true
end

return DropdownList