local class = require("libClass2")
local Frame = require("yawl-e.widget.Frame")
local keyboard = require('keyboard')

local ScrollFrame = class(Frame)

function ScrollFrame:new(parent, x, y)
    checkArg(1, parent, 'table', 'nil')
    checkArg(2, x, 'number', 'nil')
    checkArg(3, y, 'number', 'nil')
    x = x or 1
    y = y or 1
    
    local o = self.parent(parent, x, y)
    setmetatable(o, {__index = self})
    o:propagateFirst(true)
    return o
end

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

function ScrollFrame:defaultCallback(_, eventName, uuid, x, y, button, playerName)
    if eventName=="scroll" then 
        local currentScrollX, currentScrollY = self:scrollX(), self:scrollY()
        if keyboard.isControlDown() then
            local minX, maxX = self:minimumScrollX(), self:maximumScrollX()
            if (button == -1 and currentScrollX-button >= (minX or 2)) or (button == 1 and currentScrollX-button <= (maxX or -2)) then
                self:scrollX(button)
                return true
            end
        else
            local minY, maxY = self:minimumScrollY(), self:maximumScrollY()
            if (button == 1 and currentScrollY-button >= (minY or 0)) or (button == -1 and currentScrollY-button <= (maxY or 0)) then
                self:scrollY(-button)
                return true
            end
        end
    end 
end

return ScrollFrame