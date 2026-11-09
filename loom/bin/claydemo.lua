-- Loom clay demo, all one Shader: metaballs form two clay fighters out of one puddle, they fight, melt
-- back together, and the blob opens a portal onto a morphing Julia set, which drains into a black hole.
-- The top bar shows the live Lua cost and frame rate. Ctrl+C to exit.
local component, computer, event = require("component"), require("computer"), require("event")
local gpu = component.gpu
local oldW, oldH = gpu.getResolution()
gpu.setResolution(80, 26)
local loom = require("loom")
local gui = loom.widget

local W, H = 80, 50 -- shader pixels (80x25 cells, two pixels per cell)
local FLOOR = 45
local T = 0.56 -- field threshold: one ball's surface sits at its radius
local START, END = nil, 50

local floor, sqrt, sin, cos, abs, max, min, log = math.floor, math.sqrt, math.sin, math.cos, math.abs, math.max, math.min, math.log
local function clamp(v, a, b) return v < a and a or v > b and b or v end
local function smooth(k) k = clamp(k, 0, 1) return k * k * (3 - 2 * k) end
local function outBack(k) k = clamp(k, 0, 1) - 1 return 1 + 2.7 * k * k * k + 1.7 * k * k end
local function lerp(a, b, k) return a + (b - a) * k end
-- keys: {time, value[, ease]}; eases toward each key from the one before
local function track(t, keys)
    if t <= keys[1][1] then return keys[1][2] end
    for i = 2, #keys do
        local k = keys[i]
        if t < k[1] then
            local p = keys[i - 1]
            return p[2] + (k[2] - p[2]) * (k[3] or smooth)((t - p[1]) / (k[1] - p[1]))
        end
    end
    return keys[#keys][2]
end
local function rgb(r, g, b)
    return (clamp(floor(r + 0.5), 0, 255) << 16) | (clamp(floor(g + 0.5), 0, 255) << 8) | clamp(floor(b + 0.5), 0, 255)
end

-- The two fighters. Orange faces right, blue faces left.
local COLOR = {{226, 122, 48}, {58, 122, 222}}
local FIG = {
    {s = 1,
     x = {{0, 40}, {2.5, 40}, {4.5, 24}, {7, 24}, {8.6, 31}, {10.55, 31}, {10.8, 26}, {11.4, 28}, {11.9, 36}, {12.5, 34}, {14.6, 34}, {15.6, 40}},
     form = {{0, 0}, {4.5, 0}, {7, 1}, {14.8, 1}, {16.3, 0}},
     fdx = {{8.9, 6}, {9.12, 13}, {9.5, 6}, {11.4, 6}, {11.75, 3}, {12.05, 9}, {12.6, 6}},
     fdy = {{8.9, -15}, {9.12, -18}, {9.5, -15}, {11.4, -15}, {11.75, -28}, {12.05, -13}, {12.6, -15}},
     fr = {{11.4, 2.3}, {11.75, 4.6}, {12.3, 4.6}, {12.8, 2.3}},
     hit = {{10.5, 0}, {10.6, -3}, {11.0, 0}}},
    {s = -1,
     x = {{0, 40}, {2.5, 40}, {4.5, 56}, {7, 56}, {8.6, 49}, {9.15, 49}, {9.45, 54}, {10.0, 52}, {10.45, 48}, {10.9, 50}, {14.6, 50}, {15.6, 40}},
     form = {{0, 0}, {4.5, 0}, {7, 1}, {12.0, 1}, {12.6, 0}, {13.3, 0}, {14.3, 1}, {14.8, 1}, {16.3, 0}},
     fdx = {{10.2, 6}, {10.45, 10}, {10.9, 6}},
     fdy = {{10.2, -15}, {10.45, -14}, {10.9, -15}},
     spike = {{10.2, 0}, {10.45, 7}, {10.9, 0}},
     q = {{11.95, 1}, {12.2, 0.3}, {12.6, 0.3}, {13.3, 1}},
     hit = {{9.1, 0}, {9.2, 3}, {9.7, 0}}},
}
-- skeleton: dx (toward the enemy), dy (up from the floor), radius
local SKEL = {{0, -20, 3.2}, {0, -14.5, 3.4}, {0, -10.5, 3.2}, {0, -7, 3.0},
    {-2, -4.2, 2.3}, {2, -4.2, 2.3}, {-2.6, -1.3, 2.3}, {2.6, -1.3, 2.3}}
local HITS = {
    {t = 9.12, x = 46, y = FLOOR - 21, team = 2, n = 4, dir = 1},
    {t = 10.55, x = 33, y = FLOOR - 14, team = 1, n = 4, dir = -1},
    {t = 12.05, x = 48, y = FLOOR - 13, team = 2, n = 7, dir = 0},
}

local balls, nb = {}, 0
local function add(x, y, r, team)
    if r > 0.3 then
        balls[nb + 1], balls[nb + 2], balls[nb + 3], balls[nb + 4] = x, y, r, team
        nb = nb + 4
    end
end

local function heap(team, i, cx, t)
    local off = ((i - 0.5) / 12 - 0.5) * 16 + (team == 1 and -0.7 or 0.7) + 1.4 * sin(i * 2.3 + team)
    return cx + off, FLOOR - 2 - 3.2 * max(0, 1 - (off / 9) ^ 2) + 0.5 * sin(t * 3 + i * 1.7), 2.7
end

local function figure(team, t, gather)
    local F = FIG[team]
    local s, x, form = F.s, track(t, F.x), track(t, F.form)
    local q = F.q and track(t, F.q) or 1
    local bob = -abs(sin(t * 5.5 + team * 1.3)) * 0.9 * clamp(form * 2 - 1, 0, 1)
    local hitX = track(t, F.hit)
    local fx, fy, fr = F.fdx and track(t, F.fdx) or 6, F.fdy and track(t, F.fdy) or -15, F.fr and track(t, F.fr) or 2.3
    -- arms: shoulder, elbow, fist; back arm in guard
    local parts = {}
    for i = 1, #SKEL do parts[i] = SKEL[i] end
    parts[#parts + 1] = {(3 + fx) / 2, (-15 + fy) / 2 + 1.5, 1.9}
    parts[#parts + 1] = {fx, fy, fr}
    parts[#parts + 1] = {3, -12.5, 1.9}
    parts[#parts + 1] = {4.5, -12, 2.1}
    local spike = F.spike and track(t, F.spike) or 0
    for i = 1, #parts do
        local p = parts[i]
        local delay = -p[2] / 22 * 0.7
        local e = outBack(clamp(form * 1.7 - delay, 0, 1))
        local hx, hy, hr = heap(team, i, x, t)
        local dx = p[1] + ((i <= 2) and hitX * s or 0)
        local px, py, r = lerp(hx, x + dx * s, e), lerp(hy, FLOOR + p[2] * q + bob, e), lerp(hr, p[3], clamp(e, 0, 1.2))
        if gather then
            local a = i * 2.4 + team * 0.9
            px, py, r = lerp(px, 40 + 3 * cos(a + t), gather.g), lerp(py, 27 + 3 * sin(a + t), gather.g), lerp(r, 4.4, gather.g) * gather.size
        end
        add(px, py, r, team)
    end
    if spike > 0.2 then
        for k = 1, 4 do add(x + (fx + spike * k / 4 * 1.3) * s, FLOOR + fy, 1.9 - k * 0.25, team) end
    end
end

local function droplets(t)
    for _, h in ipairs(HITS) do
        local dt = t - h.t
        if dt > 0 then
            for j = 1, h.n do
                local dir = h.dir ~= 0 and h.dir or (j % 2 == 0 and 1 or -1)
                local vx, vy = dir * (16 + 12 * j / h.n), -(14 + 7 * sin(j * 1.9))
                local r = 1.3 + 0.5 * (j % 2)
                local land = (-vy + sqrt(vy * vy + 140 * (FLOOR - r - h.y))) / 70
                local owner = track(t, FIG[h.team].x)
                if dt < land then
                    add(h.x + vx * dt, h.y + vy * dt + 35 * dt * dt, r, h.team)
                else
                    local lx = clamp(h.x + vx * land, 2, W - 1)
                    local k = smooth((dt - land) / 1.4)
                    add(lerp(lx, owner, k), FLOOR - r * (1 - k), r * (1 - k), h.team)
                end
            end
        end
    end
end

-- Field: the sum of every ball's (1 - d²/R²)², R = 2r, splatted into a grid once per frame.
local Fld, FA, Shadow = {}, {}, {}
local now, portal, julia, bh = 0, 0, nil, nil
local function update()
    local t = computer.uptime() - START
    if t > END then t = END end
    now = t
    nb = 0
    local gather = t > 16.6 and {g = outBack((t - 16.6) / 1.8), size = 1 - smooth((t - 18.8) / 1.0)} or nil
    figure(1, t, gather)
    figure(2, t, gather)
    droplets(t)
    for i = 1, W * H do Fld[i], FA[i] = 0, 0 end
    for x = 1, W do Shadow[x] = 0 end
    for b = 1, nb, 4 do
        local bx, by, r, team = balls[b], balls[b + 1], balls[b + 2], balls[b + 3]
        local R = 2 * r
        local R2 = R * R
        for py = max(1, floor(by - R)), min(H, floor(by + R) + 1) do
            local dy2 = (py - by) ^ 2
            local row = (py - 1) * W
            for px = max(1, floor(bx - R)), min(W, floor(bx + R) + 1) do
                local d2 = (px - bx) ^ 2 + dy2
                if d2 < R2 then
                    local w = 1 - d2 / R2
                    w = w * w
                    local i = row + px
                    Fld[i] = Fld[i] + w
                    if team == 1 then FA[i] = FA[i] + w end
                end
            end
        end
        local lift = max(0, 1 - (FLOOR - by) / 30)
        for px = max(1, floor(bx - 1.6 * r)), min(W, floor(bx + 1.6 * r) + 1) do
            Shadow[px] = Shadow[px] + max(0, 1 - abs(px - bx) / (1.6 * r)) * 0.12 * lift
        end
    end
    portal = t > 18.6 and 64 * smooth((t - 18.6) / 2.2) ^ 1.5 or 0
    if t > 18.6 then
        local a = math.pi + 1.0 * sin((t - 18.6) * 0.42 - 1.2)
        julia = {cx = 0.7885 * cos(a), cy = 0.7885 * sin(a), zoom = 1 + 0.5 * smooth((t - 26) / 9), t = t}
    end
    if t > 33 then
        local rs = 8 * smooth((t - 33) / 3) + smooth((t - 37) / 13)
        bh = {rs = rs, rin = rs * 1.25, rout = rs * 4.6, f = 0.2 - 0.06 * smooth((t - 37) / 13), t = t,
            drain = smooth((t - 33) / 4.5), glow = smooth((t - 34.5) / 3)}
    end
end

local LX, LY, LZ = -0.48, -0.62, 0.62
local function clay(x, y)
    local i = (y - 1) * W + x
    local f = Fld[i]
    if f < T then
        if y > FLOOR then
            if y == FLOOR + 1 then return 0xcc9240 end
            return Shadow[x] > 0.25 and 0x664940 or 0x996d40 -- exact palette tones: wood and its shadow
        end
        return y > 12 and rgb(44, 40, 52) or rgb(34, 30, 42)
    end
    local gx = (x < W and Fld[i + 1] or f) - (x > 1 and Fld[i - 1] or f)
    local gy = (y < H and Fld[i + W] or f) - (y > 1 and Fld[i - W] or f)
    local nx, ny, nz = -gx, -gy, 0.35
    local len = sqrt(nx * nx + ny * ny + nz * nz)
    local diff = max(0, (nx * LX + ny * LY + nz * LZ) / len)
    local lum = 0.42 + 0.7 * diff
    if f < T + 0.09 then lum = lum * 0.55 end
    local spec = diff > 0.93 and 70 or 0
    local a = FA[i] / f + 0.22 * sin(x * 0.55 + y * 0.35 + sin(y * 0.4 - x * 0.2) * 2 + now * 0.8)
    local C = a > 0.5 and COLOR[1] or COLOR[2]
    if abs(a - 0.5) < 0.06 then lum = lum * 0.8 end -- a darker seam where the clays meet
    return rgb(C[1] * lum + spec, C[2] * lum + spec, C[3] * lum + spec)
end

local TAU = 2 * math.pi
local LOG2 = log(2)
local PAL = {{8, 20, 70}, {30, 90, 200}, {80, 200, 240}, {240, 250, 255}, {255, 190, 60}, {200, 70, 30}, {60, 20, 60}}
local function fractal(x, y)
    local j = julia
    local scale = 3.3 / W / j.zoom
    local zx, zy = (x - 40.5) * scale, (y - 25.5) * scale
    local cx, cy = j.cx, j.cy
    local n, x2, y2 = 0, zx * zx, zy * zy
    while n < 40 and x2 + y2 < 16 do
        zy = 2 * zx * zy + cy
        zx = x2 - y2 + cx
        x2, y2 = zx * zx, zy * zy
        n = n + 1
    end
    if n == 40 then return rgb(14, 10, 34) end
    local mu = n + 1 - log(log(sqrt(x2 + y2))) / LOG2
    local u = (mu * 0.06 + j.t * 0.05) % 1 * #PAL
    local k = floor(u)
    local p, q = PAL[k + 1], PAL[(k + 1) % #PAL + 1]
    u = u - k
    return rgb(lerp(p[1], q[1], u), lerp(p[2], q[2], u), lerp(p[3], q[3], u))
end

-- Black hole: shadow, photon ring, a tilted accretion disk (Doppler-brightened on the side coming
-- toward us, streaks orbiting faster inside), the far side of the disk lensed over the top, and the
-- sky behind bent around it.
local HEAT = {{0, 0, 0}, {90, 18, 8}, {200, 80, 20}, {250, 160, 50}, {255, 225, 150}, {255, 255, 240}}
local function heat(v)
    v = clamp(v, 0, 0.999) * (#HEAT - 1)
    local k = floor(v)
    local p, q = HEAT[k + 1], HEAT[k + 2]
    v = v - k
    return rgb(lerp(p[1], q[1], v), lerp(p[2], q[2], v), lerp(p[3], q[3], v))
end
local function disk(b, rho, ud, vd, dim)
    local phi = math.atan(vd, ud)
    local streak = 0.85 + 0.15 * sin(phi * 2 + rho * 0.3 - b.t * 5 * (b.rin / rho) ^ 1.5)
    local doppler = 1 - 0.5 * ud / rho
    return heat((b.rin / rho) ^ 1.1 * doppler * streak * 0.8 * dim)
end
local function hash(ix, iy)
    local h = (ix * 374761393 + iy * 668265263) & 0xffffffff
    h = ((h ~ (h >> 13)) * 1274126177) & 0xffffffff
    return (h & 0xffff) / 65536
end
local function blackhole(x, y)
    local b = bh
    local u, v = x - 40.5, y - 25.5
    local r = sqrt(u * u + v * v) + 1e-6
    local rs = b.rs
    local rho = sqrt(u * u + (v / b.f) ^ 2)
    local edge = b.rin + (b.rout - b.rin) * b.glow -- the disk grows outward from the ring as it lights
    if rho > b.rin and rho < edge and (v > 0 or r > rs * 1.05) then return disk(b, rho, u, v / b.f, 1) end
    if r < rs then return 0 end
    if r < rs + 0.9 then return heat(0.95 * (1 - 0.25 * u / r)) end
    local up = -v / r -- the far side of the disk, bent over the top (and a thin sliver under)
    local w = (up > 0 and 3.6 * up ^ 0.6 or 1.6 * (-up) ^ 1.5) * rs / 8
    local k = (r - rs - 0.9) / w
    if k < b.glow then return disk(b, b.rin + k * (b.rout - b.rin) * 0.3, -u, 1, 0.9) end
    local r2 = r - rs * rs * 1.6 / r
    local a = math.atan(v, u)
    local d = b.drain
    if d < 1 then -- the fractal spirals in: each pixel samples it farther out, turned more near the middle
        local rf = r2 * (1 + 5 * d * d)
        if rf < 47 then
            local aa = a + d * 9 / (r / 6 + 1)
            return fractal(40.5 + rf * cos(aa), 25.5 + rf * sin(aa))
        end
    end
    local sx, sy = 40.5 + r2 * cos(a), 25.5 + r2 * sin(a)
    local h = hash(floor(sx + b.t * 1.2), floor(sy))
    if h < 0.014 then return h < 0.005 and 0xffffff or 0x6d6d8a end
    return 0x0a0a1a
end

local root = gui.Frame()
root:backgroundColor(0x101018)
local bar = gui.TextLabel(root, 1, 1, "", 0xc8cce8)
bar:width(80)
local shader = gui.Shader(root, 1, 2, W, H // 2, function(x, y)
    if bh then return blackhole(x, y) end
    if portal > 0 then
        local d = sqrt((x - 40) ^ 2 + (y - 27) ^ 2)
        if d < portal - 1.2 then return fractal(x, y) end
        if d < portal then return 0xe8f4ff end
    end
    return clay(x, y)
end)
shader:dither(false)
shader:animated(true)

local draws, last, fps = 0, nil, 0
local draw = root.draw
root.draw = function(self)
    START = START or computer.uptime()
    update()
    local r = draw(self)
    draws = draws + 1
    local u = computer.uptime()
    last = last or u
    if u - last >= 1 then fps, draws, last = draws / (u - last), 0, u end
    local ms = shader:stats()
    local what = bh and ("Black hole  horizon r = %.1f px"):format(bh.rs) or julia and ("Julia set  c = %.2f %+.2fi"):format(julia.cx, julia.cy) or ("metaballs: %d balls"):format(nb // 4)
    bar:text((" loom Shader   %s   %.0f ms Lua   %.0f fps"):format(what, ms, fps))
    if now >= END then shader:animated(false) end
    return r
end

local interrupted = event.listen("interrupted", function() loom.stop() end)
loom.run(root, 0.05)
event.cancel(interrupted)
root:Destroy()
gpu.setResolution(oldW, oldH)
require("term").clear()
print("Closed clay demo")
