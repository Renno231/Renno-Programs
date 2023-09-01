local class = require("libClass2")
local Frame = require("yawl-e.widget.Frame")

local ScrollFrame = class(Frame) 
    --extends frame object
function ScrollFrame:scrollX(num)
    checkArg(1, num, 'number', 'nil')
    local oldValue = self._scrollindexX or 0
    if (num) then self._scrollindexX = (self._scrollindexX or oldValue) + num end
    return oldValue
end

function ScrollFrame:scrollY(num)
    checkArg(1, num, 'number', 'nil')
    local oldValue = self._scrollindexY or 0
    if (num) then self._scrollindexY = (self._scrollindexY or oldValue) + num end
    return oldValue
end

return ScrollFrame