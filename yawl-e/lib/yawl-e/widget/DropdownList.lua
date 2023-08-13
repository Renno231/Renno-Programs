local SortedList = require("yawl-e.widget.SortedList")
local class = require('libClass2')

local Text = require("yawl-e.widget.Text")
local DropdownList = class(Text)

function DropdownList:new(parent, x, y, width, height, backgroundColor, listobj)
    checkArg(1, parent, 'table')
    checkArg(2, x, 'number')
    checkArg(3, y, 'number')
    checkArg(4, width, 'number')
    checkArg(5, height, 'number')
    checkArg(6, backgroundColor, 'number')
    checkArg(6, listobj, 'table','nil')
    local o = self.parent(parent, x, y)
    setmetatable(o, {__index = self})
    o._list = listobj or SortedList(parent, x, y+height, width, 5, backgroundColor)
    o._dropped = false
    ---@cast o DropdownList
    o:size(width, height)
    o:backgroundColor(backgroundColor or 0)
    return o
end

function DropdownList:value(val) --number index in list or nil

end

function DropdownList:list(newlist) -- e.g., dropdown:list():sorter(function(...) end)
    checkArg(1, newlist, 'table', 'nil')
    return self._list
end

function DropdownList:drop() --boolean or nil

end

function DropdownList:toggle()
    return self:drop(not self:drop())
end

function DropdownList:animatedDrop(value) -- boolean or nil
    --tell the :draw() to lerp the list instead
end

function DropdownList:defaultCallback()
    
end

function DropdownList:listSize() --to enforce size when dropped

end

function DropdownList:charSet() --optional characters for the non-dropped and dropped states that prefix the shown value
    -- + and - for undropped and dropped?
end

function DropdownList:draw()
    --if self._list has a format function, use it on the selected value
    --list height used is the min of current height and given height
end

return DropdownList