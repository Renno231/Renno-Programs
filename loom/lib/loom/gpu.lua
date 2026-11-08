-- The GPU as seen by widgets. Outside a root frame's draw every call goes straight to the GPU.
-- During a root draw (record ... finish) the drawing calls are only logged, and colours are kept
-- in Lua. At the end the log is compared with the previous frame's: an unchanged frame costs no
-- GPU calls at all (the root's buffer still holds it); a changed one is replayed onto the buffer.
-- Reading the buffer mid-frame (`get`) applies the calls logged so far first, then draws directly
-- for the rest of that frame.
local real = require("component").gpu
local rset, rfill, rcopy, rget = real.set, real.fill, real.copy, real.get
local rgetBG, rgetFG, rsetBG, rsetFG = real.getBackground, real.getForeground, real.setBackground, real.setForeground

local gpu = setmetatable({frames = 0}, {__index = real})

local recording, direct = false, false
local log, last, n, same, applied -- this frame's calls, the previous frame's, count, equal so far, count applied
local bg, fg, bgPalette, fgPalette -- colours as drawn so far

local function put(v)
    n = n + 1
    if same and last[n] ~= v then same = false end
    log[n] = v
end

-- Run the logged calls after `applied`. `applied` moves past each call before it runs, so a call
-- that fails (bad arguments from a widget) is skipped, as it would have failed alone when drawn directly.
local function replay()
    while applied < n do
        local i = applied + 1
        local op = log[i]
        if op == "s" then applied = i + 4 rset(log[i + 1], log[i + 2], log[i + 3], log[i + 4])
        elseif op == "F" then applied = i + 5 rfill(log[i + 1], log[i + 2], log[i + 3], log[i + 4], log[i + 5])
        elseif op == "b" then applied = i + 2 rsetBG(log[i + 1], log[i + 2])
        elseif op == "f" then applied = i + 2 rsetFG(log[i + 1], log[i + 2])
        elseif op == "c" then applied = i + 6 rcopy(log[i + 1], log[i + 2], log[i + 3], log[i + 4], log[i + 5], log[i + 6])
        else applied = i end -- the starting colours
    end
end
local function apply() while not pcall(replay) do end end

---Start recording a root frame's draw. `frame` keeps the call logs between draws.
---`gpu.frames` counts root draws, so widgets can tell whether they were drawn in the latest one.
function gpu.record(frame)
    log, last = frame._drawLog or {}, frame._lastDrawLog or {}
    n, applied, same, recording, direct = 0, 0, true, true, false
    gpu.frames = gpu.frames + 1
    bg, bgPalette = rgetBG()
    fg, fgPalette = rgetFG()
    bgPalette, fgPalette = bgPalette or false, fgPalette or false
    put(bg) put(fg)
end

---Stop recording. If the frame's drawing calls differ from its previous draw, put the frame into
---the active buffer and return true.
function gpu.finish(frame)
    local changed = not same or n ~= frame._lastDrawCount
    if changed then apply() end
    recording, direct = false, false
    frame._drawLog, frame._lastDrawLog, frame._lastDrawCount = last, log, n
    log, last = nil, nil
    return changed
end

function gpu.get(x, y)
    if recording and not direct then apply() direct = true end
    return rget(x, y)
end

function gpu.getBackground()
    if recording then return bg, bgPalette end
    return rgetBG()
end

function gpu.getForeground()
    if recording then return fg, fgPalette end
    return rgetFG()
end

function gpu.setBackground(color, palette)
    if not recording then return rsetBG(color, palette) end
    local old = bg
    palette = palette or false
    if color ~= bg or palette ~= bgPalette then
        bg, bgPalette = color, palette
        put("b") put(color) put(palette)
        if direct then applied = n rsetBG(color, palette) end
    end
    return old
end

function gpu.setForeground(color, palette)
    if not recording then return rsetFG(color, palette) end
    local old = fg
    palette = palette or false
    if color ~= fg or palette ~= fgPalette then
        fg, fgPalette = color, palette
        put("f") put(color) put(palette)
        if direct then applied = n rsetFG(color, palette) end
    end
    return old
end

function gpu.set(x, y, value, vertical)
    if not recording then return rset(x, y, value, vertical) end
    put("s") put(x) put(y) put(value) put(vertical or false)
    if direct then applied = n return rset(x, y, value, vertical) end
    return true
end

function gpu.fill(x, y, width, height, char)
    if not recording then return rfill(x, y, width, height, char) end
    put("F") put(x) put(y) put(width) put(height) put(char)
    if direct then applied = n return rfill(x, y, width, height, char) end
    return true
end

function gpu.copy(x, y, width, height, tx, ty)
    if not recording then return rcopy(x, y, width, height, tx, ty) end
    put("c") put(x) put(y) put(width) put(height) put(tx) put(ty)
    if direct then applied = n return rcopy(x, y, width, height, tx, ty) end
    return true
end

return gpu
