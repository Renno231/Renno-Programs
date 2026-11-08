-- The GPU as seen by widgets. Outside a root frame's draw every call goes straight to the GPU.
-- During a root draw (record ... finish) it keeps the active buffer's colours in Lua, so setting
-- the colour that is already set costs no component call, and it logs every drawing call so the
-- root can tell whether the frame differs from the previous one before pushing it to the screen.
local real = require("component").gpu
local rset, rfill, rcopy = real.set, real.fill, real.copy
local rgetBG, rgetFG, rsetBG, rsetFG = real.getBackground, real.getForeground, real.setBackground, real.setForeground

local gpu = setmetatable({}, {__index = real})

local recording = false
local log, last, n, same -- this frame's calls, the previous frame's calls, count, equal so far
local bg, fg -- the active buffer's colours while recording

local function put(v)
    n = n + 1
    if same and last[n] ~= v then same = false end
    log[n] = v
end

---Start recording a root frame's draw. `frame` keeps the call logs between draws.
function gpu.record(frame)
    log, last = frame._drawLog or {}, frame._lastDrawLog or {}
    n, same, recording = 0, true, true
    bg, fg = rgetBG(), rgetFG()
    put(bg) put(fg)
end

---Stop recording. Return true if the frame's drawing calls differ from its previous draw.
function gpu.finish(frame)
    recording = false
    local changed = not same or n ~= frame._lastDrawCount
    frame._drawLog, frame._lastDrawLog, frame._lastDrawCount = last, log, n
    log, last = nil, nil
    return changed
end

function gpu.getBackground()
    if recording then return bg, false end
    return rgetBG()
end

function gpu.getForeground()
    if recording then return fg, false end
    return rgetFG()
end

function gpu.setBackground(color, palette)
    if not recording then return rsetBG(color, palette) end
    local old = bg
    if palette then
        rsetBG(color, palette)
        bg = rgetBG()
        put("b") put(bg)
    elseif color ~= bg then
        rsetBG(color)
        bg = color
        put("b") put(color)
    end
    return old
end

function gpu.setForeground(color, palette)
    if not recording then return rsetFG(color, palette) end
    local old = fg
    if palette then
        rsetFG(color, palette)
        fg = rgetFG()
        put("f") put(fg)
    elseif color ~= fg then
        rsetFG(color)
        fg = color
        put("f") put(color)
    end
    return old
end

function gpu.set(x, y, value, vertical)
    if recording then put("s") put(x) put(y) put(value) put(vertical or false) end
    return rset(x, y, value, vertical)
end

function gpu.fill(x, y, width, height, char)
    if recording then put("F") put(x) put(y) put(width) put(height) put(char) end
    return rfill(x, y, width, height, char)
end

function gpu.copy(x, y, width, height, tx, ty)
    if recording then put("c") put(x) put(y) put(width) put(height) put(tx) put(ty) end
    return rcopy(x, y, width, height, tx, ty)
end

return gpu
