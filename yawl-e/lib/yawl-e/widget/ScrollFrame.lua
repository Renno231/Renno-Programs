local class = require("libClass2")
local Frame = require("yawl-e.widget.Frame")

local ScrollFrame = class(Frame) 
ScrollFrame:propagateFirst(true)
    --extends frame object
function ScrollFrame:scrollX(num, override)
    checkArg(1, num, 'number', 'nil')
    checkArg(2, override, 'boolean','nil')
    local oldValue = self._scrollindexX or 0
    if (num) then self._scrollindexX = override and num or ((self._scrollindexX or oldValue) + num) end
    return oldValue
end

function ScrollFrame:minimumScrollX(num)
    checkArg(1, num, 'number', 'boolean', 'nil')
    local oldValue = self._minimumScrollX
    if type(num) == "number" then self._minimumScrollX = num end
    if num == false then self._minimumScrollX = nil end
    return oldValue
end

function ScrollFrame:maximumScrollX(num)
    checkArg(1, num, 'number', 'boolean', 'nil')
    local oldValue = self._maximumScrollX
    if type(num) == "number" then self._maximumScrollX = num end
    if num == false then self._maximumScrollX = nil end
    return oldValue
end

function ScrollFrame:scrollY(num, override)
    checkArg(1, num, 'number', 'nil')
    checkArg(2, override, 'boolean','nil')
    local oldValue = self._scrollindexY or 0
    if (num) then self._scrollindexY = override and num or ((self._scrollindexY or oldValue) + num) end
    return oldValue
end

function ScrollFrame:minimumScrollY(num)
    checkArg(1, num, 'number', 'boolean', 'nil')
    local oldValue = self._minimumScrollY
    if type(num) == "number" then self._minimumScrollY = num end
    if num == false then self._minimumScrollY = nil end
    return oldValue
end

function ScrollFrame:maximumScrollY(num)
    checkArg(1, num, 'number', 'boolean', 'nil')
    local oldValue = self._maximumScrollY
    if type(num) == "number" then self._maximumScrollY = num end
    if num == false then self._maximumScrollY = nil end
    return oldValue
end


return ScrollFrame