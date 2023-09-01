---@class yawlUtils
local unicode = require("unicode")
unicode.charAt = function(str, index) return unicode.sub(str, index, index) end
local utils = {}

---Take a color int (hex) and return it's red green and blue components
---@param hex number
---@return number
---@return number
---@return number
function utils.colorToRGB(hex)
    assert(hex >= 0 and hex <= 0xffffff)
    local r = (hex & 0xff0000) >> 16
    local g = (hex & 0x00ff00) >> 8
    local b = (hex & 0x0000ff)
    return r, g, b
end

---Take a RGB value and convert it to a color value
---@param r number
---@param g number
---@param b number
---@return number
---@overload fun(rgb:table):number
function utils.RGBtoColor(r, g, b)
    assert(r >= 0x00 and r <= 0xff)
    assert(g >= 0x00 and g <= 0xff)
    assert(b >= 0x00 and b <= 0xff)
    if (type(r) == "table") then
        b = r[3]
        g = r[2]
        r = r[1]
    end
    return b + (g << 8) + (r << 16)
end

local function splitWords(Lines, limit)
    while #Lines[#Lines] > limit do
        Lines[#Lines+1] = Lines[#Lines]:sub(limit+1)
        Lines[#Lines-1] = Lines[#Lines-1]:sub(1,limit)
    end
end

function utils.wrap(str, limit)
    local Lines, here, limit, found = {}, 1, limit or 72, (str or ""):find("(%s+)()(%S+)()")
    if not str then return Lines end
    if found then
        Lines[1] = string.sub(str,1,found-1)  -- Put the first word of the string in the first index of the table.
    else Lines[1] = str end

    str:gsub("(%s+)()(%S+)()",
        function(sp, st, word, fi)  -- Function gets called once for every space found.
            splitWords(Lines, limit)

            if fi-here > limit then
                here = st
                Lines[#Lines+1] = word                                             -- If at the end of a line, start a new table index...
            else Lines[#Lines] = Lines[#Lines].." "..word end  -- ... otherwise add to the current table index.
        end)

    splitWords(Lines, limit)

    return Lines
end

function utils.formatNumberShort(number)
    if type(number) ~= "number" then return "" end
    local absNum = math.abs(number)
    local units = { "", "k", "m", "b", "t" } -- Add more units for larger numbers if needed
    local currentUnit = 1

    while absNum >= 1000 and currentUnit < #units do
        absNum = absNum / 1000
        currentUnit = currentUnit + 1
    end

    local formattedNumber = string.format("%.2f", absNum)

    -- Check if the decimal part is zero and adjust formatting accordingly
    local integerPart, decimalPart = formattedNumber:match("(%d+)%.(%d+)")
    if decimalPart then
        if decimalPart == "00" then
            formattedNumber = string.format("%d", integerPart)
        elseif decimalPart:sub(2) == "0" then
            formattedNumber = string.format("%.1f", absNum)
        end
    end

    return formattedNumber .. units[currentUnit]
end

local Tab = {} --designed to be used in Window widget
Tab.__index = Tab

function Tab:new(parent, name, x, y)
    checkArg(1, parent, 'table')
    checkArg(2, name, 'string')
    checkArg(3, x, 'number')
    checkArg(4, y, 'number')
    local o = {}
    setmetatable(o, self)
    
    o.removeChild = parent.removeChild
    o._childs = {}
    o._parent = parent
    o._name = name
    o._displayName = name
    o._tabX = x
    o._tabY = y
    o._scrollX, o._scrollY = 0, 0 
    o._lastSelected = 0
    return o
end
--{_childs = {}, parent = somewindow, displayName = string, tabX = num, tabY = num, scrollX = num, scrollY = num,  }
function Tab:addChild(child) 
    table.insert(self._childs, child)
    child:setParent(self._parent, false) 
end

function Tab:displayName(text)
    checkArg(1, text, 'function', 'string', 'nil')
    local oldValue = self._displayName --type(self._displayName) == 'function' and self._displayName() or self._displayName
    if text~=nil then
        self._displayName = text
    end
    return oldValue
end

utils.Tab = Tab
    
return utils