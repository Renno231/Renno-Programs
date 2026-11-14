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
local mtype, tointeger = math.type, math.tointeger

local gpu = setmetatable({frames = 0}, {__index = real})

-- Each logged call is S = 3 values, so the logs stay small (two are kept, this frame's and the
-- last) and comparing two calls takes three compares:
--   at      x, y, a, b (12 bits each, offset by 2048) and the kind (2 bits) in one integer
--   colours background and foreground in one integer, 25 bits each: an RGB colour, or 2^24 + a
--           palette index
--   text    "s" set: the text (a, b unused). "F" fill: the char (a = width, b = height).
-- A call with a value that doesn't fit (a fractional or far-off coordinate, an odd colour, or
-- arguments the GPU would refuse) and every copy is logged as false, false, {kind, x, y, a, b, c,
-- d, bg, bgPalette, fg, fgPalette}. A new table never equals the last frame's, so such a call
-- always counts as changed: right, only slower. (Copies replay the whole frame anyway.)
local S = 3
local SET, VERTICAL, FILL = 0, 1, 2
local recording, direct = false, false
local log, n, applied -- this frame's calls, values logged, values replayed
local whole -- this frame must be replayed whole (it copies)
local cutWide -- a clipped replay cut text with wide characters, which can't be cut by index
local bg, fg, bgPalette, fgPalette -- colours as drawn so far
local bgCode, fgCode, key -- the same packed (nil if a colour doesn't fit), and both in one (or false)
local cbg, cfg, cbgPalette, cfgPalette -- colours on the real GPU while replaying
local ckey -- the packed colours the real GPU has, if set from a packed call
-- Parts (gpu.part): a widget that animates alone marks the calls it logs, so a frame only it needs
-- redoes just those (gpu.redo). Each part is {widget, from, to, bg, bgPalette, fg, fgPalette}: its
-- calls are log values from + 1 .. to, drawn starting with those colours.
local parts -- this root draw's parts, in log order
local redoing = false
local scratch = {} -- a redone part's calls (gpu.release frees it)

-- A colour as 25 bits, or nil if it doesn't fit.
local function code(color, palette)
    if mtype(color) ~= "integer" then
        if mtype(color) ~= "float" then return end
        color = tointeger(color)
        if not color then return end
    end
    if palette == true then
        if color >= 0 and color < 16 then return 0x1000000 | color end
    elseif not palette and color >= 0 and color <= 0xFFFFFF then
        return color
    end
end

local function int(v)
    if mtype(v) == "float" then return tointeger(v) end
    if mtype(v) == "integer" then return v end
end
-- x, y, a, b and the kind in one integer, or nil if a value doesn't fit.
local function pack(kind, x, y, a, b)
    if mtype(x) ~= "integer" or mtype(y) ~= "integer" or mtype(a) ~= "integer" or mtype(b) ~= "integer" then
        x, y, a, b = int(x), int(y), int(a), int(b)
        if not (x and y and a and b) then return end
    end
    x, y, a, b = x + 2048, y + 2048, a + 2048, b + 2048
    if (x | y | a | b) & -4096 ~= 0 then return end -- outside -2048..2047
    return x << 38 | y << 26 | a << 14 | b << 2 | kind
end

-- Log a call that can't be packed. (Packed calls are logged inline in set and fill, the hot path.
-- In OpenComputers string patterns and unicode calls allocate; recording uses neither.)
local function box(kind, x, y, a, b, c, d)
    local i = n
    log[i + 1], log[i + 2], log[i + 3] = false, false, {kind, x, y, a, b, c, d, bg, bgPalette, fg, fgPalette}
    n = i + S
end

-- Logged call i (its index - 1) of `l` as kind, x, y, a, b, c, d.
local function call(l, i)
    local at = l[i + 1]
    if not at then
        local raw = l[i + 3]
        return raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7]
    end
    local kind, x, y = at & 3, (at >> 38) - 2048, (at >> 26 & 0xFFF) - 2048
    if kind == FILL then return "F", x, y, (at >> 14 & 0xFFF) - 2048, (at >> 2 & 0xFFF) - 2048, l[i + 3] end
    return "s", x, y, l[i + 3], kind == VERTICAL
end

local function setColours(b, bp, f, fp)
    if b ~= cbg or bp ~= cbgPalette then cbg, cbgPalette = b, bp rsetBG(b, bp) end
    if f ~= cfg or fp ~= cfgPalette then cfg, cfgPalette = f, fp rsetFG(f, fp) end
end
-- Give the real GPU the colours of logged call i. Callers skip it when they equal ckey.
local function colours(i)
    local c = log[i + 2]
    if not c then
        local raw = log[i + 3]
        ckey = nil
        return setColours(raw[8], raw[9], raw[10], raw[11])
    end
    local b, f = c >> 25, c & 0x1FFFFFF
    setColours(b & 0xFFFFFF, b > 0xFFFFFF, f & 0xFFFFFF, f > 0xFFFFFF)
    ckey = c
end

-- Draw logged call i (its index - 1), clipped to x1..x2, y1..y2 when given.
local function draw(i, x1, y1, x2, y2)
    local at, kind, x, y, a, b, c, d = log[i + 1]
    if at then -- decoded here, not by call(): this runs for every logged call of a changed frame
        x, y = (at >> 38) - 2048, (at >> 26 & 0xFFF) - 2048
        if at & 3 == FILL then
            kind, a, b, c = "F", (at >> 14 & 0xFFF) - 2048, (at >> 2 & 0xFFF) - 2048, log[i + 3]
        else
            kind, a, b = "s", log[i + 3], at & 3 == VERTICAL
        end
    else
        kind, x, y, a, b, c, d = call(log, i)
    end
    if kind == "F" then
        if x1 then
            local l, t, r, bottom = max(x, x1), max(y, y1), min(x + a - 1, x2), min(y + b - 1, y2)
            if l > r or t > bottom then return end
            x, y, a, b = l, t, r - l + 1, bottom - t + 1
        end
        if log[i + 2] ~= ckey then colours(i) end
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
        if log[i + 2] ~= ckey then colours(i) end
        rset(x, y, a, b)
    else
        rcopy(x, y, a, b, c, d)
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
    cbg, cfg, cbgPalette, cfgPalette, ckey = nil, nil, nil, nil, nil
    applied, cutWide = 0, false
    while not pcall(replay, x1, y1, x2, y2) do end
end

-- Grow the box x1, y1, x2, y2 by the area of logged calls from..to (indexes - 1) of `l`.
local function bounds(l, from, to, x1, y1, x2, y2)
    for i = from, to - 1, S do
        local kind, x, y, w, h, c, d = call(l, i)
        if kind == "s" then
            if h then w, h = 1, ulen(w) else w, h = uwlen(w), 1 end
        elseif kind == "c" then
            x, y = x + c, y + d
        end
        if w > 0 and h > 0 then
            x1, y1, x2, y2 = min(x1, x), min(y1, y), max(x2, x + w - 1), max(y2, y + h - 1)
        end
    end
    return x1, y1, x2, y2
end

-- The rectangle covering every call that differs between `old` and this frame's log.
local function damage(old, oldN)
    local new, m, p, s = log, min(n, oldN), 0, 0
    while p < m and new[p + 1] == old[p + 1] and new[p + 2] == old[p + 2] and new[p + 3] == old[p + 3] do p = p + S end
    local i, j = n - S, oldN - S
    while s < m - p and new[i + 1] == old[j + 1] and new[i + 2] == old[j + 2] and new[i + 3] == old[j + 3] do
        s, i, j = s + S, i - S, j - S
    end
    local x1, y1, x2, y2 = bounds(new, p, n - s, huge, huge, -huge, -huge)
    return bounds(old, p, oldN - s, x1, y1, x2, y2)
end

---Start recording a root frame's draw. `frame` keeps the call logs between draws.
---`gpu.frames` counts root draws, so widgets can tell whether they were drawn in the latest one.
function gpu.record(frame)
    log, parts = frame._drawLog or {}, {}
    n, applied, whole, recording, direct = 0, 0, false, true, false
    gpu.frames = gpu.frames + 1
    bg, bgPalette = rgetBG()
    fg, fgPalette = rgetFG()
    bgPalette, fgPalette = bgPalette or false, fgPalette or false
    bgCode, fgCode = code(bg, bgPalette), code(fg, fgPalette)
    key = bgCode and fgCode and (bgCode << 25 | fgCode) or false
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
    frame._parts, log, parts = parts, nil, nil
    return changed, x1, y1, x2, y2
end

---While a root frame is recorded, start `widget`'s part: the calls it logs until `gpu.partEnd`.
---A frame that only this widget needs then redoes just them (`gpu.redo`). A part must not read
---the screen (`get`) or copy. Returns the part, or nil when no root draw is being recorded.
function gpu.part(widget)
    if not recording or redoing then return end
    local p = {widget, n, n, bg, bgPalette, fg, fgPalette}
    parts[#parts + 1] = p
    return p
end
---End a part started by `gpu.part` (nil does nothing).
function gpu.partEnd(p) if p then p[3] = n end end

-- The cells of a redo's box (row-major from 1), one integer each: the last call covering the cell
-- (its index, + 1, 0 for none) in the log before the part (bits 0-19), in the part's old calls
-- (20-39) and in its new ones (40-59), and bit 60 when the log after the part covers it. Then each
-- cell holds the call to draw there, + 1 (0: unchanged). Kept between redos (gpu.release frees it).
local grid = {}
local UNDER, WAS, NOW, AFTER, FIELD = 0, 20, 40, 1 << 60, 0xFFFFF
-- The changed runs of a redo (call, x, y, last x, and the call's colours), and their drawing order:
-- by colours, so each colour is set once.
local runCall, runX, runY, runEnd, runKey, order = {}, {}, {}, {}, {}, {}
local function byColours(a, b) return runKey[a] < runKey[b] end

---Free what redos keep between frames. loom.run calls it when no widget animates alone.
function gpu.release()
    scratch, grid, runCall, runX, runY, runEnd, runKey, order = {}, {}, {}, {}, {}, {}, {}, {}
end

-- Put in `shift`'s field of each cell of the box x1..x2, y1..y2 (w wide) the last of calls
-- from..to (indexes - 1) of `l` that covers it (shift nil: set the AFTER bit).
local function cover(l, from, to, x1, y1, x2, y2, w, shift)
    local keep = shift and ~(FIELD << shift)
    for i = from, to - S, S do
        local at, x, y, cw, ch = l[i + 1], nil, nil, nil, nil
        if at then
            x, y = (at >> 38) - 2048, (at >> 26 & 0xFFF) - 2048
            local kind = at & 3
            if kind == FILL then
                cw, ch = (at >> 14 & 0xFFF) - 2048, (at >> 2 & 0xFFF) - 2048
            elseif x <= x2 and y <= y2 and (kind == VERTICAL or y >= y1) then -- measure only text that may reach the box
                if kind == VERTICAL then cw, ch = 1, ulen(l[i + 3]) else cw, ch = uwlen(l[i + 3]), 1 end
            else
                cw, ch = 0, 0
            end
        else
            local kind, c, d
            kind, x, y, cw, ch, c, d = call(l, i)
            if kind == "s" then
                if ch then cw, ch = 1, ulen(cw) else cw, ch = uwlen(cw), 1 end
            elseif kind == "c" then
                x, y = x + c, y + d
            end
        end
        local left, top, right, bottom = max(x, x1), max(y, y1), min(x + cw - 1, x2), min(y + ch - 1, y2)
        for row = top, bottom do
            local at0 = (row - y1) * w - x1 + 1
            if shift then
                local v = (i + 1) << shift
                for col = left, right do grid[at0 + col] = grid[at0 + col] & keep | v end
            else
                for col = left, right do grid[at0 + col] = grid[at0 + col] | AFTER end
            end
        end
    end
end

-- Whether call i of `a` and call j of `b` put the same thing in a cell: fills of the same character
-- and colours, or the same text call.
local function same(a, i, b, j)
    local p, q = a[i + 1], b[j + 1]
    if not p or not q or a[i + 2] ~= b[j + 2] or a[i + 3] ~= b[j + 3] then return false end
    return p == q or (p & 3 == FILL and q & 3 == FILL)
end

---Redo `widget`'s part of `frame`'s last draw: `redraw()` logs the widget's calls again and they
---replace its part of the log. Every call covers whole cells, so a cell shows the last call over
---it: only the cells whose last call now puts something else there are drawn, so what was drawn
---under or over the widget stays as it was. Returns like `gpu.finish`: false if nothing changed
---(or the widget had no part in that draw), else true and the changed rectangle (none when it all
---had to be replayed). The frame's buffer must be active.
function gpu.redo(frame, widget, redraw)
    local all, p = frame._parts, nil
    for i = 1, all and #all or 0 do if all[i][1] == widget then p = all[i] break end end
    if not p then return false end
    local old, oldN, from, to = frame._lastDrawLog, frame._lastDrawCount, p[2], p[3]
    log, n, recording, redoing, direct = scratch, 0, true, true, false
    bg, bgPalette, fg, fgPalette = p[4], p[5], p[6], p[7]
    bgCode, fgCode = code(bg, bgPalette), code(fg, fgPalette)
    key = bgCode and fgCode and (bgCode << 25 | fgCode) or false
    local ok, err = pcall(redraw)
    local m = n
    recording, redoing, log = false, false, nil
    if not ok then error(err, 0) end
    if m == to - from then
        local unchanged = true
        for i = 1, m do if scratch[i] ~= old[from + i] then unchanged = false break end end
        if unchanged then return false end
    end
    local x1, y1, x2, y2 = bounds(scratch, 0, m, huge, huge, -huge, -huge)
    x1, y1, x2, y2 = bounds(old, from, to, x1, y1, x2, y2)
    local w, cells = x2 - x1 + 1, (x2 - x1 + 1) * (y2 - y1 + 1)
    if cells > 0 and not frame._lastWhole then
        for c = 1, cells do grid[c] = 0 end
        cover(old, 0, from, x1, y1, x2, y2, w, UNDER)
        cover(old, from, to, x1, y1, x2, y2, w, WAS)
        cover(scratch, 0, m, x1, y1, x2, y2, w, NOW)
        cover(old, to, oldN, x1, y1, x2, y2, w, nil)
        for c = 1, cells do
            local g, change = grid[c], 0
            if g < AFTER then -- else a later call still covers it
                local under, was, now = g & FIELD, g >> WAS & FIELD, g >> NOW
                local shown = was > 0 and was or under -- the call that put there what is there now
                if now > 0 then
                    if not (shown > 0 and same(old, shown - 1, scratch, now - 1)) then change = from + now end
                elseif was > 0 then
                    change = under -- uncovered: what was under the part shows again
                end
            end
            grid[c] = change
        end
    end
    local delta = m - (to - from)
    if delta ~= 0 then -- make room (or close the gap), and move the parts after this one
        table.move(old, to + 1, oldN, to + 1 + delta)
        for i = oldN + delta + 1, oldN do old[i] = nil end
        for i = 1, #all do
            local q = all[i]
            if q ~= p and q[2] >= to then q[2], q[3] = q[2] + delta, q[3] + delta end
        end
    end
    table.move(scratch, 1, m, from + 1, old)
    p[3] = from + m
    frame._lastDrawCount = oldN + delta
    if cells <= 0 then return false end
    -- Draw onto the buffer, then leave the real colours as they were.
    local b, bp = rgetBG()
    local f, fp = rgetFG()
    log, n = old, oldN + delta
    local dx1, dy1, dx2, dy2 = huge, huge, -huge, -huge
    if frame._lastWhole then -- copies read what was drawn before them: replay it all
        apply()
        dx1, dy1, dx2, dy2 = nil, nil, nil, nil
    else
        local count = 0
        for y = y1, y2 do
            local at0 = (y - y1) * w - x1 + 1
            local x = x1
            while x <= x2 do
                local v = grid[at0 + x]
                if v > 0 then
                    local i, e = v - 1, x
                    while e < x2 and grid[at0 + e + 1] == v do e = e + 1 end
                    count = count + 1
                    runCall[count], runX[count], runY[count], runEnd[count], runKey[count], order[count] = i, x, y, e, old[i + 2] or -1, count
                    x = e + 1
                else
                    x = x + 1
                end
            end
        end
        for k = count + 1, #order do order[k] = nil end
        table.sort(order, byColours)
        cbg, cfg, cbgPalette, cfgPalette, ckey, cutWide = nil, nil, nil, nil, nil, false
        for k = 1, count do
            local r = order[k]
            pcall(draw, runCall[r], runX[r], runY[r], runEnd[r], runY[r]) -- a call with bad arguments fails as it did when first drawn
        end
        if cutWide then -- text with wide characters can't be cut to a cell: replay the box
            apply(x1, y1, x2, y2)
        end
        -- The whole box is copied to the screen: its size stays the same from frame to frame, so
        -- the frame's staging buffer is kept.
        if count > 0 then dx1, dy1, dx2, dy2 = x1, y1, x2, y2 end
    end
    log = nil
    if cbg ~= nil and (cbg ~= b or cbgPalette ~= bp) then rsetBG(b, bp) end
    if cfg ~= nil and (cfg ~= f or cfgPalette ~= fp) then rsetFG(f, fp) end
    if dx1 and dx1 > dx2 then return false end
    return true, dx1, dy1, dx2, dy2
end

function gpu.get(x, y)
    if recording and not direct then
        apply()
        rsetBG(bg, bgPalette) rsetFG(fg, fgPalette)
        cbg, cfg, cbgPalette, cfgPalette, ckey = bg, fg, bgPalette, fgPalette, nil
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
    bgCode = code(color, palette)
    key = bgCode and fgCode and (bgCode << 25 | fgCode) or false
    if direct and (bg ~= cbg or bgPalette ~= cbgPalette) then cbg, cbgPalette, ckey = bg, bgPalette, nil rsetBG(color, palette) end
    return old
end

function gpu.setForeground(color, palette)
    if not recording then return rsetFG(color, palette) end
    local old = fg
    fg, fgPalette = color, palette or false
    fgCode = code(color, palette)
    key = bgCode and fgCode and (bgCode << 25 | fgCode) or false
    if direct and (fg ~= cfg or fgPalette ~= cfgPalette) then cfg, cfgPalette, ckey = fg, fgPalette, nil rsetFG(color, palette) end
    return old
end

function gpu.set(x, y, value, vertical)
    if not recording then return rset(x, y, value, vertical) end
    local t = type(value)
    if t == "number" then value, t = tostring(value), "string" end -- so it can be clipped
    local at = key and t == "string" and (not vertical or vertical == true) and pack(vertical and VERTICAL or SET, x, y, 0, 0)
    if at then
        local i = n
        log[i + 1], log[i + 2], log[i + 3] = at, key, value
        n = i + S
    else
        box("s", x, y, value, vertical or false)
    end
    if direct then applied = n return rset(x, y, value, vertical) end
    return true
end

function gpu.fill(x, y, width, height, char)
    if not recording then return rfill(x, y, width, height, char) end
    local at = key and pack(FILL, x, y, width, height)
    if at then
        local i = n
        log[i + 1], log[i + 2], log[i + 3] = at, key, char
        n = i + S
    else
        box("F", x, y, width, height, char)
    end
    if direct then applied = n return rfill(x, y, width, height, char) end
    return true
end

function gpu.copy(x, y, width, height, tx, ty)
    if not recording then return rcopy(x, y, width, height, tx, ty) end
    whole = true -- a copy reads what earlier calls drew
    box("c", x, y, width, height, tx, ty)
    if direct then applied = n return rcopy(x, y, width, height, tx, ty) end
    return true
end

return gpu
