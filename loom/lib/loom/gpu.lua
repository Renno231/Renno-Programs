-- The GPU as seen by widgets. Outside a root frame's draw every call goes straight to the GPU.
-- During a root draw (record ... finish) drawing calls are only logged, each with the colours it
-- uses, and colours are kept in Lua. At the end the log is compared with the previous frame's:
-- an unchanged frame costs no GPU calls at all (the root's buffer still holds it). For a changed
-- one, the calls that differ (found by matching both logs from the start and from the end) give a
-- damaged rectangle; only the calls that touch it are replayed onto the buffer, clipped to it, and
-- only that rectangle needs copying to the screen. Reading the buffer mid-frame (`get`) replays
-- everything logged so far and draws directly for the rest of that frame.
local real = require("component").gpu
local unicode = require("unicode")
local rset, rfill, rcopy, rget = real.set, real.fill, real.copy, real.get
local rgetBG, rgetFG, rsetBG, rsetFG = real.getBackground, real.getForeground, real.setBackground, real.setForeground
local ulen, uwlen, usub = unicode.len, unicode.wlen, unicode.sub
local min, max, huge = math.min, math.max, math.huge

local gpu = setmetatable({frames = 0}, {__index = real})

-- Each logged call is S values: kind, x, y, a, b, c, d, bg, bgPalette, fg, fgPalette.
-- "s" set: a = text, b = vertical. "F" fill: a = width, b = height, c = char.
-- "c" copy: a = width, b = height, c = tx, d = ty.
local S = 11
local recording, direct = false, false
local log, n, applied -- this frame's calls, values logged, values replayed
local whole -- this frame must be replayed whole (it copies)
local cutWide -- a clipped replay cut text with wide characters, which can't be cut by index
local bg, fg, bgPalette, fgPalette -- colours as drawn so far
local cbg, cfg, cbgPalette, cfgPalette -- colours on the real GPU while replaying

-- (In OpenComputers string patterns and unicode calls allocate; recording uses neither.)
local function put(kind, x, y, a, b, c, d)
    local i = n
    log[i + 1], log[i + 2], log[i + 3], log[i + 4], log[i + 5], log[i + 6], log[i + 7] = kind, x, y, a, b, c, d
    log[i + 8], log[i + 9], log[i + 10], log[i + 11] = bg, bgPalette, fg, fgPalette
    n = i + S
end

local function colours(i)
    local b, bp, f, fp = log[i + 8], log[i + 9], log[i + 10], log[i + 11]
    if b ~= cbg or bp ~= cbgPalette then cbg, cbgPalette = b, bp rsetBG(b, bp) end
    if f ~= cfg or fp ~= cfgPalette then cfg, cfgPalette = f, fp rsetFG(f, fp) end
end

-- Draw logged call i (its index - 1), clipped to x1..x2, y1..y2 when given.
local function draw(i, x1, y1, x2, y2)
    local kind, x, y, a, b, c = log[i + 1], log[i + 2], log[i + 3], log[i + 4], log[i + 5], log[i + 6]
    if kind == "F" then
        if x1 then
            local l, t, r, bottom = max(x, x1), max(y, y1), min(x + a - 1, x2), min(y + b - 1, y2)
            if l > r or t > bottom then return end
            x, y, a, b = l, t, r - l + 1, bottom - t + 1
        end
        colours(i)
        rfill(x, y, a, b, c)
    elseif kind == "s" then
        if x1 then
            local from, to, length
            length = ulen(a)
            if b then -- vertical
                if x < x1 or x > x2 then return end
                from, to = max(1, y1 - y + 1), min(length, y2 - y + 1)
                y = y + from - 1
            else
                if y < y1 or y > y2 then return end
                from, to = max(1, x1 - x + 1), min(length, x2 - x + 1)
                x = x + from - 1
            end
            if from > to then return end
            if from > 1 or to < length then
                if not b and uwlen(a) ~= length then cutWide = true return end
                a = usub(a, from, to)
            end
        end
        colours(i)
        rset(x, y, a, b)
    else
        rcopy(x, y, a, b, c, log[i + 7])
    end
end

-- Replay the logged calls after `applied`, clipped when given. `applied` moves past each call
-- before it runs, so a call that fails (bad arguments from a widget) is skipped, as it would have
-- failed alone when drawn directly.
local function replay(x1, y1, x2, y2)
    while applied < n do
        local i = applied
        applied = i + S
        draw(i, x1, y1, x2, y2)
    end
end
local function apply(x1, y1, x2, y2)
    cbg, cfg, cbgPalette, cfgPalette = nil, nil, nil, nil
    applied, cutWide = 0, false
    while not pcall(replay, x1, y1, x2, y2) do end
end

-- Grow the box x1, y1, x2, y2 by the area of logged calls from..to (indexes - 1) of `l`.
local function bounds(l, from, to, x1, y1, x2, y2)
    for i = from, to - 1, S do
        local kind, x, y, w, h = l[i + 1], l[i + 2], l[i + 3], l[i + 4], l[i + 5]
        if kind == "s" then
            if h then w, h = 1, ulen(w) else w, h = uwlen(w), 1 end
        elseif kind == "c" then
            x, y = x + l[i + 6], y + l[i + 7]
        end
        if w > 0 and h > 0 then
            x1, y1, x2, y2 = min(x1, x), min(y1, y), max(x2, x + w - 1), max(y2, y + h - 1)
        end
    end
    return x1, y1, x2, y2
end

-- Are calls i of `a` and j of `b` (indexes - 1) the same?
local function same(a, i, b, j)
    for k = 1, S do
        if a[i + k] ~= b[j + k] then return false end
    end
    return true
end

-- The rectangle covering every call that differs between `old` and this frame's log.
local function damage(old, oldN)
    local m, p, s = min(n, oldN), 0, 0
    while p < m and same(log, p, old, p) do p = p + S end
    while s < m - p and same(log, n - s - S, old, oldN - s - S) do s = s + S end
    local x1, y1, x2, y2 = bounds(log, p, n - s, huge, huge, -huge, -huge)
    return bounds(old, p, oldN - s, x1, y1, x2, y2)
end

---Start recording a root frame's draw. `frame` keeps the call logs between draws.
---`gpu.frames` counts root draws, so widgets can tell whether they were drawn in the latest one.
function gpu.record(frame)
    log = frame._drawLog or {}
    n, applied, whole, recording, direct = 0, 0, false, true, false
    gpu.frames = gpu.frames + 1
    bg, bgPalette = rgetBG()
    fg, fgPalette = rgetFG()
    bgPalette, fgPalette = bgPalette or false, fgPalette or false
end

---Stop recording and bring the frame's buffer up to date. Returns false if nothing changed since
---the frame's previous draw; true if the whole frame was redrawn; or true and the changed
---rectangle x1, y1, x2, y2. Set `frame._lastDrawLog = nil` to have the next draw redrawn whole.
function gpu.finish(frame)
    local old = frame._lastDrawLog
    local changed, x1, y1, x2, y2 = true, nil, nil, nil, nil
    if direct then
        replay() -- the rest was drawn directly
    elseif not old or whole or frame._lastWhole then
        apply()
    else
        local ok
        ok, x1, y1, x2, y2 = pcall(damage, old, frame._lastDrawCount)
        if not ok then
            x1, y1, x2, y2 = nil, nil, nil, nil -- a call with bad arguments: replay it all
            apply()
        elseif x1 > x2 or y1 > y2 then
            changed, x1, y1, x2, y2 = false, nil, nil, nil, nil
        else
            apply(x1, y1, x2, y2)
            if cutWide then x1, y1, x2, y2 = nil, nil, nil, nil apply() end
        end
    end
    if changed then -- leave the real colours as the frame left them
        if cbg ~= bg or cbgPalette ~= bgPalette then rsetBG(bg, bgPalette) end
        if cfg ~= fg or cfgPalette ~= fgPalette then rsetFG(fg, fgPalette) end
    end
    recording, direct = false, false
    frame._drawLog, frame._lastDrawLog, frame._lastDrawCount, frame._lastWhole = old, log, n, whole
    log = nil
    return changed, x1, y1, x2, y2
end

function gpu.get(x, y)
    if recording and not direct then
        apply()
        rsetBG(bg, bgPalette) rsetFG(fg, fgPalette)
        cbg, cfg, cbgPalette, cfgPalette = bg, fg, bgPalette, fgPalette
        direct = true
    end
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
    bg, bgPalette = color, palette or false
    if direct and (bg ~= cbg or bgPalette ~= cbgPalette) then cbg, cbgPalette = bg, bgPalette rsetBG(color, palette) end
    return old
end

function gpu.setForeground(color, palette)
    if not recording then return rsetFG(color, palette) end
    local old = fg
    fg, fgPalette = color, palette or false
    if direct and (fg ~= cfg or fgPalette ~= cfgPalette) then cfg, cfgPalette = fg, fgPalette rsetFG(color, palette) end
    return old
end

function gpu.set(x, y, value, vertical)
    if not recording then return rset(x, y, value, vertical) end
    if type(value) == "number" then value = tostring(value) end -- so it can be clipped
    put("s", x, y, value, vertical or false)
    if direct then applied = n return rset(x, y, value, vertical) end
    return true
end

function gpu.fill(x, y, width, height, char)
    if not recording then return rfill(x, y, width, height, char) end
    put("F", x, y, width, height, char)
    if direct then applied = n return rfill(x, y, width, height, char) end
    return true
end

function gpu.copy(x, y, width, height, tx, ty)
    if not recording then return rcopy(x, y, width, height, tx, ty) end
    whole = true -- a copy reads what earlier calls drew
    put("c", x, y, width, height, tx, ty)
    if direct then applied = n return rcopy(x, y, width, height, tx, ty) end
    return true
end

return gpu
