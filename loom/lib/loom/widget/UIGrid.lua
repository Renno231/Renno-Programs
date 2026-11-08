local checkArg = require("loom.util").checkArg
local Frame = require("loom.widget.Frame")

---A frame that places its children in a grid, left to right then top to bottom, and sizes each to
---its cell. Set `columns`; cells share the width unless `cellSize` fixes it, and are one row high
---unless `cellSize` says otherwise. `rows` limits how many rows show. Removing a child gives back
---the position and size it had before it joined the grid. `scrollX`/`scrollY` move the grid.
---@class UIGrid:Frame
---@operator call:UIGrid
---@overload fun(parent?:Frame,x?:number,y?:number):UIGrid
local UIGrid = require("loom.class")(Frame)

function UIGrid:addChild(child)
    self._childData = self._childData or {}
    local x, y = child:position()
    local width, height = child:size()
    self._childData[child] = {x, y, width, height}
    return Frame.addChild(self, child)
end

function UIGrid:removeChild(child)
    local data = self._childData and self._childData[child]
    if data then
        self._childData[child] = nil
        child:position(data[1], data[2])
        child:size(data[3], data[4])
    end
    return Frame.removeChild(self, child)
end

local function getset(field, default)
    return function(self, value)
        checkArg(1, value, 'number', 'nil')
        local old = self[field] or default
        if value then self[field] = value end
        return old
    end
end

---Number of columns (default 1).
UIGrid.columns = getset("_columns", 1)
---Rows shown; children past them are hidden. 0 (default) shows every row.
UIGrid.rows = getset("_rows", 0)
---Cells between columns (default 0).
UIGrid.columnPadding = getset("_padX", 0)
---Cells between rows (default 0).
UIGrid.rowPadding = getset("_padY", 0)
---Fixed cell width. 0 (default) shares the grid's width between the columns.
UIGrid.cellWidth = getset("_cellWidth", 0)
---Cell height (default 1).
UIGrid.cellHeight = getset("_cellHeight", 1)

---@return number columnPadding,number rowPadding
function UIGrid:padding(x, y)
    return self:columnPadding(x), self:rowPadding(y)
end

---@return number cellWidth,number cellHeight
function UIGrid:cellSize(width, height)
    return self:cellWidth(width), self:cellHeight(height)
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

---Place and size every child in its cell.
---@package
function UIGrid:_calculateGrid()
    local columns, rows = math.max(1, self:columns()), self:rows()
    local padX, padY = self:padding()
    local inset = self:bordered() and 1 or 0
    local width, height = self:cellSize()
    if width <= 0 then
        width = math.max(1, (self:width() - 2 * inset - padX * (columns - 1)) // columns)
    end
    self:_sort()
    for i, child in ipairs(self._childs) do
        local column, row = (i - 1) % columns, (i - 1) // columns
        child:visible(rows <= 0 or row < rows)
        child._anims, child._layout = nil, nil -- the grid decides
        child:position(1 + inset + column * (width + padX), 1 + inset + row * (height + padY))
        child:size(width, height)
    end
end

function UIGrid:draw()
    if not self:visible() then return end
    self:_calculateGrid()
    return Frame.draw(self)
end

return UIGrid
