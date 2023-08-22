--[[
    UIGrid as a frame, on parent element size and position get stored, and un unparent get restored (overloaded parent function), 
    but during draw they forced into a grid of x columns and y rows. 
    Has padding and scrolling. Scroll moves all elements up/down/left/right by 1.
    ColumnWidth, RowHeight. Or cellWidth and cellHeight and cellSize? If unset or set to false, autofit to cols and rows
]]

local class = require("libClass2")
local Frame = require("yawl-e.widget.Frame")
local gpu = require("component").gpu

--[[
    TODO
        
]]

local UIGrid = class(Frame) 

function UIGrid:addChild(containerChild)
    self._childData = self._childData or {}
    self._childData[containerChild] = {containerChild:position(), containerChild:size()}
    table.insert(self._childs, containerChild)
end

function UIGrid:removeChild(child)
    local childId = 0
    for i, v in pairs(self._childs) do
        if (v == child) then childId = i end
    end
    if (childId > 0) then
        table.remove(self._childs, childId)
        return child
    end
    if self._childData then --restore size and position
        local cdata = self._childData[child]
        child:position(cdata[1], cdata[2])
        child:size(cdata[3], cdata[4])
        self._childData[child] = nil
    end
end

function UIGrid:columns(num)

end

function UIGrid:columnPadding(num)

end


function UIGrid:rowPadding(num)

end

function UIGrid:padding(x, y)

end

function UIGrid:rows(num)

end

function UIGrid:cellWidth(num)

end

function UIGrid:cellHeight(num)

end

function UIGrid:cellSize(width, height)
    --not finished
    self:cellWidth(width)
    self:cellHeight(height)
end

function UIGrid:scrollX(num)
    checkArg(1, num, 'number', 'nil')
    local oldValue = self._scrollindexX or 0
    if (num) then self._scrollindexX = num end
    return oldValue
end

function UIGrid:scrollY(num)
    checkArg(1, num, 'number', 'nil')
    local oldValue = self._scrollindexY or 0
    if (num) then self._scrollindexY = num end
    return oldValue
end

function UIGrid:_calculateGrid()
    local colmax, rowmax = self:columns(), self:rows()
    if #self._childs == 0 or colmax == 0 or rowmax == 0 then return end
    local width, height = self:cellSize()
    local padx, pady = self:padding()
    local scrollx, scrolly = self:scrollX(), self:scrollY()
    local col, row = 1,1
    for _, child in ipairs (self._childs) do
        --position absolutely, size as needed
        if row > rowmax then
            child:visible(false)
        else
            child:visible(true)
            if child._tweenPos then child._tweenPos = nil end
            if child._tweenSize then 
                child._tweenSize.goal.width, child._tweenSize.goal.height = math.min(width, child._tweenSize.goal.width), math.min(height, child._tweenSize.goal.height)
            end
            if child:width() > width then child:width(width) end
            if child:height() > height then child:height(height) end
            child:position((width + padx) * (col-1) - scrollx, (height + pady) * (row - 1) - scrolly)
            if col == colmax then
                col, row = 1, row + 1
            else
                col = col + 1
            end
        end
    end
end

function UIGrid:draw()
    if not self:visible() then return end
    --[[
        draw like typical frame
        not too sure how to do the positioning
        check tween size stuff and math.min() it if its out of the cellsize
    ]]
    return true
end