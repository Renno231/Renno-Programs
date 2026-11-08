-- Loom shader demo: a dithered gradient sky, a panel that slides in on a soft drop shadow, an
-- animated plasma and a shimmering progress bar. Every number shown is measured as it runs.
-- Ctrl+C to exit.
local component, computer, event = require("component"), require("computer"), require("event")

-- count GPU component calls (before loom loads, so its calls go through the counter)
local proxy = component.gpu
local calls = 0
for k, v in pairs(proxy) do
    if k ~= "address" and k ~= "type" and k ~= "slot" and (type(v) == "table" or type(v) == "function") then
        proxy[k] = function(...) calls = calls + 1 return v(...) end
    end
end

local loom = require("loom")
local gui = loom.widget
local W, H = proxy.getResolution()

local interrupted = event.listen("interrupted", function() loom.stop() end)

local function mix(a, b, k)
    local function ch(s) local x, y = (a >> s) & 0xff, (b >> s) & 0xff return math.floor(x + (y - x) * k + 0.5) << s end
    return ch(16) | ch(8) | ch(0)
end
local function scale(c, k)
    return (math.floor(((c >> 16) & 0xff) * k) << 16) | (math.floor(((c >> 8) & 0xff) * k) << 8) | math.floor((c & 0xff) * k)
end

local root = gui.Frame()
root:backgroundColor(0)

-- Sky: a vertical gradient in clean palette bands (one fill per band row).
local SKY_TOP, SKY_BOTTOM = 0x000022, 0xd04070
local function sky(py) return mix(SKY_TOP, SKY_BOTTOM, (py - 1) / (H * 2 - 1)) end
local background = gui.Shader(root, 1, 1, W, H, function(x, y) return sky(y) end)
background:dither(false)
background:z(0)

-- Panel and its shadow: the shadow is the sky darkened by a soft falloff around the panel's
-- rounded rectangle (a distance function), offset down and right. Pixels under the panel are skipped.
local PW, PH, M, OX, OY = 64, 30, 5, 2, 1
local panel = gui.Frame(root, math.floor((W - PW) / 2) + 1, H + 2)
panel:size(PW, PH)
panel:backgroundColor(0x1b1d33)
panel:foregroundColor(0x7b88e0)
panel:bordered(true)
panel:borderSet(panel.Borders.SIMPLE_LINE)
panel:z(2)

local shadow
shadow = gui.Shader(root, 1, 1, PW + 2 * M, PH + 2 * M, function(x, y)
    -- pixel coordinates inside the shadow; the panel's shadow rectangle starts at (M+1, 2M+1)
    local cx, cy = x - 0.5, (y - 0.5) / 2 -- pixel centre in cells
    if cx > M - OX and cx < M - OX + PW and cy > M - OY and cy < M - OY + PH then return nil end -- under the panel
    local hx, hy = PW / 2 - 1, PH / 2 - 0.5
    local dx = math.max(math.abs(cx - (M + PW / 2)) - hx, 0)
    local dy = math.max(math.abs(cy - (M + PH / 2)) - hy, 0) * 2 -- rows are twice as tall as columns
    local d = math.sqrt(dx * dx + dy * dy)
    local shade = math.exp(-(d / 2.2) ^ 2)
    if shade < 0.05 then return nil end -- the sky shows through
    return scale(sky(shadow:absY() * 2 - 2 + y), 1 - 0.75 * shade)
end)
shadow:z(1)
shadow:dither(false)
shadow:weld(panel, OX - M, OY - M)

gui.TextLabel(panel, 3, 2, "Loom shaders", 0xffffff)
local intro = gui.TextLabel(panel, 3, 3, "each colour comes from a function of (x, y, time)", 0x9aa3d6)
intro:width(PW - 4)

-- Plasma: four sine waves through a cosine colour palette, recomputed every frame.
local plasma = gui.Shader(panel, 3, 5, PW - 4, 14, function(x, y, t)
    local v = math.sin(x / 7 + t) + math.sin(y / 5 - t * 1.3) + math.sin((x + y) / 11 + t * 0.7)
        + math.sin(math.sqrt((x - 30) ^ 2 + (y - 14) ^ 2) / 5 - t * 1.6)
    local p = v / 8 + 0.5
    local r = 0.5 + 0.5 * math.cos(6.2832 * (p + 0.00))
    local g = 0.5 + 0.5 * math.cos(6.2832 * (p + 0.33))
    local b = 0.5 + 0.5 * math.cos(6.2832 * (p + 0.67))
    return (math.floor(r * 255) << 16) | (math.floor(g * 255) << 8) | math.floor(b * 255)
end)
plasma:animated(true)
plasma:dither(false)
local plasmaInfo = gui.TextLabel(panel, 3, 19, "", 0xffd27a)
plasmaInfo:width(PW - 4)

-- Shimmer: a progress bar with a bright band sweeping across the filled part.
local BAR = PW - 4
local bar = gui.Shader(panel, 3, 21, BAR, 1, function(x, y, t)
    local filled = BAR * ((t / 6) % 1.15)
    if x > filled then return 0x2a2c48 end
    local band = (t * 40) % (BAR + 30) - 15
    local glow = math.exp(-((x - band) / 4) ^ 2)
    return mix(0x2d6cdf, 0xe8f0ff, glow)
end)
bar:animated(true)
bar:dither(false)
local barInfo = gui.TextLabel(panel, 3, 22, "", 0xffd27a)
barInfo:width(PW - 4)

local skyInfo = gui.TextLabel(panel, 3, 24, "", 0x9aa3d6)
skyInfo:width(PW - 4)
local shadowInfo = gui.TextLabel(panel, 3, 25, "", 0x9aa3d6)
shadowInfo:width(PW - 4)
local frameInfo = gui.TextLabel(panel, 3, 27, "", 0x7dffa8)
frameInfo:width(PW - 4)
gui.TextLabel(panel, 3, 28, "Ctrl+C to exit", 0x6a6f99)

-- slide in with an overshoot
panel:animate({y = math.floor((H - PH) / 2) + 1}, 1.4, {easing = "outBack", delay = 0.5})

-- frame statistics, updated twice a second
local draws, drawMs, drawCalls = 0, 0, 0
local draw = root.draw
root.draw = function(self)
    local c0, t0 = calls, os.clock()
    local r = draw(self)
    draws, drawMs, drawCalls = draws + 1, drawMs + (os.clock() - t0) * 1000, drawCalls + calls - c0
    return r
end
local function fmt(name, shader, size)
    local ms, fills = shader:stats()
    return ("%-10s %-11s %6.1f ms  %4d fills"):format(name, size, ms, fills)
end
local last = computer.uptime()
local timer = event.timer(0.5, function()
    local now = computer.uptime()
    plasmaInfo:text(fmt("plasma", plasma, ("%dx%d px"):format(plasma:width(), plasma:height() * 2)) .. "  every frame")
    barInfo:text(fmt("shimmer", bar, ("%dx%d px"):format(bar:width(), 2)) .. "  every frame")
    skyInfo:text(fmt("sky", background, ("%dx%d px"):format(W, H * 2)) .. "  once")
    shadowInfo:text(fmt("shadow", shadow, ("%dx%d px"):format(shadow:width(), shadow:height() * 2)) .. "  when moved")
    if draws > 0 then
        frameInfo:text(("frame: %.1f fps, %.1f ms Lua, %d GPU calls"):format(draws / (now - last), drawMs / draws, drawCalls // draws))
    end
    draws, drawMs, drawCalls, last = 0, 0, 0, now
end, math.huge)

loom.run(root)
event.cancel(timer)
event.cancel(interrupted)
root:Destroy()
require("term").clear()
print("Closed shader demo")
