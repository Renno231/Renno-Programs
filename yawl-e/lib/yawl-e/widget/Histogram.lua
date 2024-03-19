local class = require("libClass2")
local Widget = require("yawl-e.widget.Widget")
local gpu = require("component").gpu
local unicode = require"unicode"
--[[
    Ideally, Histogram will have horizontal scrolling. Though there is some contention about the direction.
    needs a lot of work
        partially upgraded with MineOS stuff
        needs to have memory performance improvements
]]
---@class Histogram:Frame
---@field parent Frame
---@operator call:Histogram
---@overload fun(parent:Frame,x:number,y:number):Histogram
---@overload fun(parent:Frame,x:number,y:number,maxColumns:number):Histogram
local Histogram = class(Widget) --I think this can actually be Widget

---Comment
---@return Histogram
---@param parent Frame
---@param x number
---@param y number
---@param maxColumns? number
function Histogram:new(parent, x, y, maxColumns)
    checkArg(1, parent, "table")
    checkArg(1, maxColumns, "number", "nil")
    local o = self.parent(parent, x, y)
    setmetatable(o, {__index = self})
    ---@cast o Histogram
    o._maxColumns = maxColumns
    o._data = {}
    o:fillChar(" ")
    return o
end

--insert at the end
---@param value number
function Histogram:insert(value)
    checkArg(1, value, "number")
    table.insert(self._data, value)
    self:invokeCallback("valueAdded", value)
end

--overwride the value
---@param index number
---@param value number
---@return number
function Histogram:set(index, value)
    checkArg(1, index, 'number')
    checkArg(1, value, 'number')
    local oldValue = self._data[index]
    if (value) then
        self._data[index] = value
        self:invokeCallback("valueChanged", oldValue, value)
    end
    return oldValue
end

--change existing value
---@param value number
---@param index number
---@return number
function Histogram:adjust(value, index)
    checkArg(1, index, 'number', 'nil')
    checkArg(1, value, 'number')
    index = index or #self._data --if no chosen index, change the last
    local oldValue = self._data[index] or 0
    self._data[index] = oldValue + value
    self:invokeCallback("valueAdjusted", oldValue, self._data[index])
    return oldValue
end

--not the best name, basically used to control the vertical height
---@param value? number
---@return number
function Histogram:maxValue(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._maxValue
    if (value) then self._maxValue = value end
    return oldValue
end

---Remove all the data
function Histogram:clear()
    self._data = {}
end

---The characted used inside the graph bars
---@param value? string
---@return string
function Histogram:fillChar(value)
    checkArg(1, value, 'string', 'nil')
    local oldValue = self._fill
    if (value) then self._fill = value end
    return oldValue
end

---@param value? any
---@return any
function Histogram:fillForegroundColor(value)
    checkArg(1, value, 'string', 'nil')
    local oldValue = self._fillForegroundColor
    if (value) then self._fillForegroundColor = value end
    return oldValue
end

---@param value? number
---@return number
function Histogram:fillBackgroundColor(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._fillBackgroundColor
    if (value) then self._fillBackgroundColor = value end
    return oldValue
end

---@param value? number
---@return number
function Histogram:textForegroundColor(value)
    checkArg(1, value, 'number', 'nil')
    local oldValue = self._textForegroundColor
    if (value) then self._textForegroundColor = value end
    return oldValue
end

---@param value? string
---@return string
function Histogram:headline(value)
    checkArg(1, value, 'function', 'nil')
    local oldValue = self._headlineCallback
    if (value) then self._headlineCallback = value end
    if value == false then self._headlineCallback = nil end
    return oldValue
end

---@param name? string
---@return string
function Histogram:label(name)
    checkArg(1, name, 'string', 'nil')
    local oldValue = self._label
    if (name) then self._label = name end
    return oldValue
end

function Histogram:unit(unit)
    checkArg(1, unit, 'string', 'nil', 'boolean')
    local oldValue = self._unit
    if (unit) then self._unit = unit end
    if unit == false then self._unit = nil end
    return oldValue
end

--Histogram:addLabel(relative_x, relative_y, text) -- simple text ?
-- should be on Widget?

-- MineOS helper function
local function fillVerticalPart(obj, x1, y1, x2, y2, chartHeight)
    local dx, dy = x2 - x1, y2 - y1
    local absdx, absdy = math.abs(dx), math.abs(dy)
    if absdx >= absdy then
        local step, y = dy / absdx, y1
        for x = x1, x2, (x1 < x2 and 1 or -1) do
            local yFloor = math.floor(y)
            gpu.fill(math.floor(x), yFloor - 30, 1, math.floor(y + chartHeight) * 2 - yFloor - 1, " ")
            y = y + step
        end
    else
        local step, x = dx / absdy, x1
        for y = y1, y2, (y1 < y2 and 1 or -1) do
            local yFloor = math.floor(y)
            gpu.setBackground(0x333333) --object.colors.chart
            gpu.fill(math.floor(x), yFloor - 30, 1, math.floor(y + chartHeight) * 2 - yFloor - 1, " ")
            x = x + step
        end
    end
end

function Histogram:draw()
    if (not self:visible()) then return end
    --need to make an option to display data above or underneath of graph
    local isBordered = self:bordered()
    -- local headlineFunc = self._headlineCallback
    local x, y, width, height = self:absX() + (isBordered and 1 or 0), self:absY() + (isBordered and 1 or 0), self:width() + (isBordered and -2 or 0), 
                                self:height() + (isBordered and -2 or 0)
    if height == 0 or width == 0 then return end
    -- local xOffset, yOffset, maxValue = x + width - 1, y + height, self:maxValue() or height
    -- local totalPoints, fillChar = #self._data, self:fillChar()
    -- local mean, min, max = 0, maxValue, -1
    local fgColor, bgColor = self:foregroundColor(), self:backgroundColor()
    -- local fillfgColor, fillbgColor, txtFgColor = self:fillForegroundColor(), self:fillBackgroundColor(), self:textForegroundColor() --colors
    local oldFG, oldBG = gpu.getForeground(), gpu.getBackground()
    --draw over area
    -- if headlineFunc then
    --     height = height - 2
    -- end
    -- if fgColor then gpu.setForeground(fgColor) end
    if bgColor then 
        gpu.setBackground(bgColor)
        self:_gpufill(x, y, width, height, " ") 
    end
    -- if fillfgColor then gpu.setForeground(fillfgColor) end
    -- if fillbgColor then gpu.setBackground(fillbgColor) end
    -- local bars = math.min(width - 1, totalPoints)
    -- for i = 0, bars do
    --     local value = math.max(self._data[totalPoints - i] or 0, 0) --math max probably not necessary
    --     if value > 0 then                                           --temporary debug
    --         local pixelHeight = math.min(math.floor((value / maxValue) * height), height)
    --         if value < min then min = value end
    --         if value > max then max = value end
    --         self:_gpufill(xOffset - i, yOffset - pixelHeight, 1, pixelHeight, fillChar)
    --         mean = mean + value
    --     end
    -- end
    -- mean = mean / bars
    -- if headlineFunc then
    --     if txtFgColor then gpu.setForeground(txtFgColor) end
    --     local succ, headline, divider = pcall(headlineFunc, self:label(), self:unit(), width, min, max, maxValue, self._data[totalPoints], mean)
    --     self:_gpuset(x, y, headline or "Headline missing!")
    --     self:_gpuset(x, y + 1, divider or string.rep(unicode.char(0x1fb02), width))
    -- end
    -- MINE OS CHART
    local valuesCopy = {}
	for i = 1, #self._data do 
        valuesCopy[i] = {i, self._data[i]} --, i} 
    end
	table.sort(valuesCopy, function(a, b) return a[1] < b[1] end)
	
	if #valuesCopy == 0 then valuesCopy = {{0, 0}} end

	-- Max, min, deltas
	local xMin, xMax, yMin, yMax = valuesCopy[1][1], valuesCopy[#valuesCopy][1], valuesCopy[1][2], valuesCopy[1][2]
	
	for i = 1, #valuesCopy do
		yMin, yMax = math.min(yMin, valuesCopy[i][2]), math.max(yMax, valuesCopy[i][2])
	end
	
	local dx, dy = xMax - xMin, yMax - yMin

	-- y axis values and helpers
	local value, chartHeight, yAxisValueMaxWidth, yAxisValues = yMin, height - 1 - 1, 0, {}--(object.showXAxisValues and 1 or 0), 0, {}
	
	for cy = y + height - 3, y + 1, -chartHeight * 1 do --object.yAxisValueInterval do
		local stringValue = math.floor(value) --getAxisValue(value, object.yAxisPostfix, object.roundValues)
		
		yAxisValueMaxWidth = math.max(yAxisValueMaxWidth, unicode.wlen(stringValue))
		table.insert(yAxisValues, {y = math.ceil(cy), value = stringValue})
		value = value + dy * 1-- object.yAxisValueInterval
	end
	
	local stringValue = math.floor(yMax) --getAxisValue(yMax, object.yAxisPostfix, object.roundValues)
	table.insert(yAxisValues, {y = y, value = stringValue})
	yAxisValueMaxWidth = math.max(yAxisValueMaxWidth, unicode.wlen(stringValue))
    
	local chartWidth = width - yAxisValueMaxWidth - 2 --(object.showYAxisValues and yAxisValueMaxWidth + 2 or 0) 
	local chartX = x + width - chartWidth
	
    if fgColor then gpu.setForeground(fgColor) end
	for i = 1, #yAxisValues do
		-- if object.showYAxisValues then
			gpu.set(chartX - unicode.wlen(yAxisValues[i].value) - 2, yAxisValues[i].y, tostring(yAxisValues[i].value))
		-- end
        -- gpu.setForeground(0)
		self:_gpuset(chartX, yAxisValues[i].y, string.rep("─", chartWidth))
	end

	-- x axis values
	-- if object.showXAxisValues then
		value = xMin
        gpu.setForeground(0xffffff) --object.colors.axisValue
		for x = chartX, chartX + chartWidth - 2, chartWidth * 1 do --self._xAxisValueInterval do
			local stringValue = math.floor(value + 0.5) --getAxisValue(value, object.xAxisPostfix, object.roundValues)
			gpu.set(math.floor(x - unicode.wlen(stringValue) / 2), y + height - 1, tostring(stringValue))
			value = value + dx * 1 --self._xAxisValueInterval
		end
		local value = math.floor(xMax) --getAxisValue(xMax, object.xAxisPostfix, object.roundValues)
        --gpu.setForeground(object.colors.axisValue)
        --x axis tick marks and lines
		gpu.set(x + width - unicode.wlen(value), y + height - 1, tostring(value))
	-- end

	-- y Axis tick marks and lines
    gpu.setForeground(0) --object.colors.axis
	for cy = y, y + chartHeight - 1 do
		self:_gpuset(chartX - 1, cy, "┨")
	end
    gpu.setForeground(0) --object.colors.axis
	self:_gpuset(chartX - 1, y + chartHeight, "┗" .. string.rep("┯━", math.floor(chartWidth / 2)))
	-- chart
    gpu.setBackground(0xff00ff)
	for i = 1, #valuesCopy - 1 do
		local newx = math.floor(chartX + (valuesCopy[i][1] - xMin) / dx * (chartWidth - 1))
		local newy = math.floor(y + chartHeight - 1 - (valuesCopy[i][2] - yMin) / dy * (chartHeight - 1)) * 2
		local xNext = math.floor(chartX + (valuesCopy[i + 1][1] - xMin) / dx * (chartWidth - 1))
		local yNext = math.floor(newy + chartHeight - 1 - (valuesCopy[i + 1][2] - yMin) / dy * (chartHeight - 1)) * 2
		-- if object.fillChartArea then
			fillVerticalPart(self, newx, newy, xNext, yNext, chartHeight)
		-- else
			--self:_gpufill(x, y, xNext, yNext, " ") --object.colors.chart)
		-- end
	end
    gpu.setBackground(oldBG)
    gpu.setForeground(oldFG)
    return true
end

--[[
local characters = {" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
local charsV = {" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
local charsH = {" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"}]]

return Histogram
--[[
function GUI.chart(x, y, width, height, axisColor, axisValueColor, axisHelpersColor, chartColor, xAxisValueInterval, yAxisValueInterval, xAxisPostfix, yAxisPostfix, fillChartArea, values)
	local object = GUI.object(x, y, width, height)

	object.colors = {axis = axisColor, chart = chartColor, axisValue = axisValueColor, helpers = axisHelpersColor}
	object.draw = drawChart
	object.values = values or {}
	object.xAxisPostfix = xAxisPostfix
	object.yAxisPostfix = yAxisPostfix
	object.xAxisValueInterval = xAxisValueInterval
	object.yAxisValueInterval = yAxisValueInterval
	object.fillChartArea = fillChartArea
	object.showYAxisValues = true
	object.showXAxisValues = true

	return object
end ]]