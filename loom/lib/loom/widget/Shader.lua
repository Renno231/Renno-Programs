local checkArg = require("loom.util").checkArg
local computer = require("computer")
local gpu = require("loom.gpu")
local run = require("loom.run")
local Widget = require("loom.widget.Widget")

---A rectangle painted by a function, like a pixel shader: `shade(x, y, t, width, height)` returns
---the colour at (x, y), counted from 1 inside the widget, `t` seconds after it started. By default
---each cell is two pixels tall (half-block characters), so `height` is twice the widget's height.
---Return nil to leave a pixel unpainted.
---
---Cost is mostly GPU calls, so the drawing merges neighbouring cells of the same colours into one
---fill, and on 8-bit screens dithers colours to the palette (which also makes long runs of equal
---colours). A still shader is worked out once and replayed until its size or position changes;
---`animated(true)` reworks it every frame at `fps` frames per second.
---@class Shader:Widget
---@operator call:Shader
---@overload fun(parent:Frame,x:number,y:number,width:number,height:number,shade:function):Shader
local Shader = require("loom.class")(Widget)

local HALF = "▀"

---@param parent Frame
---@param x number
---@param y number
---@param width number
---@param height number
---@param shade function
---@return Shader
function Shader:new(parent, x, y, width, height, shade)
    checkArg(4, width, 'number')
    checkArg(5, height, 'number')
    checkArg(6, shade, 'function')
    local o = self.parent(parent, x, y)
    setmetatable(o, self)
    ---@cast o Shader
    o:size(width, height)
    o._shade = shade
    o._start = computer.uptime()
    return o
end

local function getset(field, default, kind)
    return function(self, value)
        checkArg(1, value, kind, 'nil')
        local old = self[field]
        if old == nil then old = default end
        if value ~= nil then self[field], self._ops = value, nil end
        return old
    end
end

---The shading function. Setting it redraws.
Shader.shade = getset("_shade", nil, 'function')
---Rework the picture every frame (for shaders that use `t`). Default false.
Shader.animated = getset("_animated", false, 'boolean')
---Frames per second while animated. Default 20.
Shader.fps = getset("_fps", 20, 'number')
---Two pixels per cell, using half-block characters. Default true.
Shader.halfBlocks = getset("_half", true, 'boolean')
---On 8-bit screens colours snap to the palette; `dither(true)` (default) mixes neighbouring palette
---colours in a 4x4 pattern for in-between shades, `false` gives clean bands and far fewer fills.
function Shader:dither(value)
    checkArg(1, value, 'boolean', 'nil')
    local old = self._dither
    if old == nil then old = true end
    if value ~= nil then self._dither, self._ops = value, nil end
    return old
end

---Redraw a still shader (after something its function reads has changed).
function Shader:refresh()
    self._ops = nil
    run.request(0)
end

---Cost of the last reworked frame: milliseconds of Lua, and fills (each one GPU call plus colour changes).
---@return number ms,number fills
function Shader:stats() return self._ms or 0, self._fills or 0 end

-- Ordered (Bayer 4x4) dithering to OpenComputers' 8-bit palette: a 6x8x5 colour cube (6 reds,
-- 8 greens, 5 blues) plus 16 greys, 0x0f0f0f to 0xf0f0f0. The cube has no greys between black and
-- white, so a colour nearer a palette grey than the cube snaps to the greys.
local bayer = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5}
local function levels(n)
    local t = {}
    for i = 0, n - 1 do t[i] = math.floor(i * 255 / (n - 1) + 0.5) end
    return t
end
local R, G, B = levels(6), levels(8), levels(5)
local function clamp(v, top) return math.max(0, math.min(top, v)) end
local function quantize(color, x, y, dither)
    local d = dither and bayer[(y % 4) * 4 + x % 4 + 1] / 16 - 0.46875 or 0 -- about -0.47 .. 0.47
    local r, g, b = (color >> 16) & 0xff, (color >> 8) & 0xff, color & 0xff
    -- nearest cube colour and nearest grey (undithered), to pick which the pixel belongs to
    local cr, cg, cb = R[math.floor(r * 5 / 255 + 0.5)], G[math.floor(g * 7 / 255 + 0.5)], B[math.floor(b * 4 / 255 + 0.5)]
    local level = (r + g + b) / 3
    local grey = clamp(math.floor(level / 15 + 0.5), 16) * 15 -- 0 and 255 (black, white) are in the cube
    if grey == 240 and level > 247.5 then grey = 255 end
    local cubeDist = (r - cr) ^ 2 + (g - cg) ^ 2 + (b - cb) ^ 2
    local greyDist = (r - grey) ^ 2 + (g - grey) ^ 2 + (b - grey) ^ 2
    if greyDist < cubeDist then
        local i = clamp(math.floor(level / 15 + 0.5 + d), 17)
        local v = i == 17 and 255 or i * 15
        return (v << 16) | (v << 8) | v
    end
    return (R[clamp(math.floor(r * 5 / 255 + d + 0.5), 5)] << 16) | (G[clamp(math.floor(g * 7 / 255 + d + 0.5), 7)] << 8)
        | B[clamp(math.floor(b * 4 / 255 + d + 0.5), 4)]
end

---Work out the picture as runs: {top, bottom, x, y, length, ...} relative to the widget.
---@private
function Shader:_build(t)
    local width, height = self:width(), self:height()
    local shade, half = self._shade, self:halfBlocks()
    local dither = self:dither()
    local snap = gpu.getDepth() == 8 -- snap to the palette even undithered, so equal cells merge
    local ops, top, bottom = {}, {}, {}
    local pixels = half and height * 2 or height
    local n = 0
    for row = 1, height do
        local py = half and row * 2 - 1 or row
        for col = 1, width do
            local a = shade(col, py, t, width, pixels)
            local b = half and shade(col, py + 1, t, width, pixels) or a
            if a == nil then a = b elseif b == nil then b = a end
            if snap and a then
                a = quantize(a, col, py, dither)
                b = half and quantize(b, col, py + 1, dither) or a
            end
            top[col], bottom[col] = a or false, b or false
        end
        local col = 1
        while col <= width do
            local a, b = top[col], bottom[col]
            local length = 1
            while col + length <= width and top[col + length] == a and bottom[col + length] == b do
                length = length + 1
            end
            if a then
                ops[n + 1], ops[n + 2], ops[n + 3], ops[n + 4], ops[n + 5] = a, b, col, row, length
                n = n + 5
            end
            col = col + length
        end
    end
    -- Runs never overlap, so draw them grouped by colour (background first): each colour is then
    -- set once per frame instead of once per run.
    local groups, keys = {}, {}
    for i = 1, n, 5 do
        local key = ops[i + 1] << 24 | ops[i]
        local group = groups[key]
        if not group then group = {} groups[key] = group keys[#keys + 1] = key end
        group[#group + 1] = i
    end
    if #keys * 5 == n then return ops end -- every run has its own colours
    table.sort(keys)
    local sorted, m = {}, 0
    for k = 1, #keys do
        local group = groups[keys[k]]
        for g = 1, #group do
            local i = group[g]
            sorted[m + 1], sorted[m + 2], sorted[m + 3], sorted[m + 4], sorted[m + 5] = ops[i], ops[i + 1], ops[i + 2], ops[i + 3], ops[i + 4]
            m = m + 5
        end
    end
    return sorted
end

function Shader:draw()
    if not self:visible() then return end
    local x, y = self:absX(), self:absY()
    local ops = self._ops
    local animated = self:animated()
    if animated or not ops or self._opsX ~= x or self._opsY ~= y or self._opsW ~= self:width() or self._opsH ~= self:height() then
        local t0 = os.clock()
        ops = self:_build(computer.uptime() - self._start)
        self._ms = (os.clock() - t0) * 1000
        self._fills = #ops // 5
        self._ops, self._opsX, self._opsY, self._opsW, self._opsH = ops, x, y, self:width(), self:height()
    end
    if animated then run.request(1 / self:fps()) end
    local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()
    local bg, fg = oldBG, oldFG
    for i = 1, #ops, 5 do
        local a, b = ops[i], ops[i + 1]
        local cx, cy = x + ops[i + 2] - 1, y + ops[i + 3] - 1
        if b ~= bg then gpu.setBackground(b) bg = b end
        if a == b then
            self:_gpufill(cx, cy, ops[i + 4], 1, " ")
        else
            if a ~= fg then gpu.setForeground(a) fg = a end
            self:_gpufill(cx, cy, ops[i + 4], 1, HALF)
        end
    end
    gpu.setBackground(oldBG)
    gpu.setForeground(oldFG)
    return true
end

return Shader
