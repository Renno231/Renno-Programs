-- Loom regression tests. Runs on an OpenComputers machine (see run.ps1): builds widgets, feeds
-- them real signals with computer.pushSignal, reads the screen back, and checks draw budgets.
-- Writes PASS/FAIL lines to /home/loomtest.txt, then prints "loomtest done".
local component, computer, event = require("component"), require("computer"), require("event")
local unicode = require("unicode")

-- count every GPU component call (loom.gpu captures the proxy's functions when it loads)
local proxy = component.gpu
local calls, byName, lastBlit = 0, {}, nil
for k, v in pairs(proxy) do
    if k ~= "address" and k ~= "type" and k ~= "slot" and (type(v) == "table" or type(v) == "function") then
        proxy[k] = function(...)
            calls = calls + 1 byName[k] = (byName[k] or 0) + 1
            if k == "bitblt" then lastBlit = {...} end
            return v(...)
        end
    end
end

local loom = require("loom")
local gui = loom.widget
local input = require("loom.input")
local screen = proxy.getScreen()
local kb = component.list("keyboard")()
local W, H = proxy.getResolution()

local out, failed = {}, 0
local function check(name, ok, detail)
    if not ok then failed = failed + 1 end
    out[#out + 1] = (ok and "PASS " or "FAIL ") .. name .. (detail and ("  " .. tostring(detail)) or "")
end
local function eq(name, got, want) check(name, got == want, ("got %q want %q"):format(tostring(got), tostring(want))) end

-- deliver queued signals to the listeners
local function pump() repeat until not event.pull(0) end
local function touch(x, y, button) computer.pushSignal("touch", screen, x, y, button or 0, "tester") pump() end
local CTRL, SHIFT = 29, 42
local function key(char, code, player)
    computer.pushSignal("key_down", kb, char, code, player or "tester")
    computer.pushSignal("key_up", kb, char, code, player or "tester")
    pump()
end
local function hold(code, f)
    computer.pushSignal("key_down", kb, 0, code, "tester") pump()
    f()
    computer.pushSignal("key_up", kb, 0, code, "tester") pump()
end
local function type_(str) for c in str:gmatch(".") do key(c:byte(), 0) end end
local function row(y, x, n) -- screen text at row y
    local s = {}
    for i = x, x + n - 1 do s[#s + 1] = (proxy.get(i, y)) end
    return table.concat(s)
end
local K = {back = 14, del = 211, left = 203, right = 205, up = 200, down = 208, home = 199, ["end"] = 207, enter = 28, tab = 15, esc = 1}

local function scene()
    local root = gui.Frame()
    root:backgroundColor(0)
    return root
end

local ok, err = xpcall(function()

-- TextInput: typing, editing keys, words, paste, submit -----------------------------------------
do
    local root = scene()
    local field = gui.TextInput(root, 5, 3, "")
    field:size(10, 1)
    field:backgroundColor(0x113355)
    local submitted
    field:on("submit", function(_, text) submitted = text end)
    root:draw()
    touch(6, 3)
    check("touch focuses", field:focused())
    type_("hello world")
    eq("typed", field:text(), "hello world")
    eq("cursor at end", field:cursor(), 11)
    key(8, K.back)
    eq("backspace", field:text(), "hello worl")
    hold(CTRL, function() key(0, K.left) end)
    eq("ctrl+left", field:cursor(), 6)
    key(0, K.home)
    eq("home", field:cursor(), 0)
    key(0, K.del)
    eq("delete", field:text(), "ello worl")
    key(0, K["end"])
    hold(CTRL, function() key(8, K.back) end)
    eq("ctrl+backspace", field:text(), "ello ")
    computer.pushSignal("clipboard", kb, "pasted\n", "tester") pump()
    eq("paste drops trailing newline", field:text(), "ello pasted")
    key(0, K.right)
    eq("right at end stays", field:cursor(), 11)
    root:draw()
    -- 10 cells wide, cursor after 11 chars: the view scrolls so the cursor cell is the last one
    eq("scrolls to cursor", row(3, 5, 9), "lo pasted")
    key(66, 0, "intruder")
    eq("other player's keys ignored", field:text(), "ello pasted")
    key(13, K.enter)
    eq("enter submits", submitted, "ello pasted")
    check("enter leaves the field", not field:focused())
    root:draw()
    eq("blur shows the start", row(3, 5, 10), "ello paste")
    touch(5 + 2, 3)
    eq("touch places cursor", field:cursor(), 2)
    touch(1, 20)
    check("touch elsewhere blurs", not field:focused())
    root:Destroy()
end

-- maxLength, mask, placeholder, clearOnEnter ------------------------------------------------------
do
    local root = scene()
    local field = gui.TextInput(root, 2, 2, "")
    field:size(12, 1)
    field:maxLength(4)
    field:mask("*")
    field:placeholder("password")
    root:draw()
    eq("placeholder shown", row(2, 2, 8), "password")
    field:focus("tester")
    type_("secret")
    eq("maxLength", field:text(), "secr")
    root:draw()
    eq("masked", row(2, 2, 4), "****")
    field:clearOnEnter(true)
    key(13, K.enter)
    eq("clearOnEnter clears", field:text(), "")
    check("clearOnEnter keeps focus", field:focused())
    key(0, K.esc)
    check("escape blurs", not field:focused())
    root:Destroy()
end

-- Multiline: newlines, up/down keep the column --------------------------------------------------
do
    local root = scene()
    local field = gui.TextInput(root, 2, 2, "")
    field:size(20, 4)
    check("tall field is multiline", field:multilines())
    field:focus()
    type_("abcdef") key(13, K.enter) type_("ab") key(13, K.enter) type_("abcdefgh")
    eq("multiline text", field:text(), "abcdef\nab\nabcdefgh")
    key(0, K.left) key(0, K.left) -- column 7 of line 3
    key(0, K.up)
    eq("up clamps to short line", table.concat({field:cursorXY()}, ","), "3,2")
    key(0, K.up)
    eq("up keeps goal column", table.concat({field:cursorXY()}, ","), "7,1")
    key(0, K.home)
    eq("home goes to line start", table.concat({field:cursorXY()}, ","), "1,1")
    hold(CTRL, function() key(13, K.enter) end)
    check("ctrl+enter submits", not field:focused())
    root:draw()
    eq("multiline drawn", row(3, 2, 2) .. "|" .. row(4, 2, 8), "ab|abcdefgh")
    root:Destroy()
end

-- Tab order follows the screen, Shift+Tab goes back -----------------------------------------------
do
    local root = scene()
    local a = gui.TextInput(root, 2, 2, "a")
    local c = gui.TextInput(root, 2, 6, "c")
    local b = gui.TextInput(root, 30, 2, "b")
    for _, f in ipairs({a, b, c}) do f:size(5, 1) end
    root:draw()
    a:focus()
    key(9, K.tab)
    check("tab goes right", b:focused())
    key(9, K.tab)
    check("tab goes down", c:focused())
    key(9, K.tab)
    check("tab wraps", a:focused())
    hold(SHIFT, function() key(9, K.tab) end)
    check("shift+tab goes back", c:focused())
    c:visible(false)
    root:draw()
    key(9, K.tab)
    check("tab skips hidden fields", a:focused())
    a:Destroy()
    check("destroy releases focus", input.focused() == nil)
    root:Destroy()
end

-- on/off handlers and the old callback --------------------------------------------------------------
do
    local root = scene()
    local front = gui.Rectangle(root, 2, 2, 10, 3, 0x666666)
    local got, rootHit, legacy = nil, 0, nil
    local h = front:on("touch", function(_, scr, x, y, button, player) got = table.concat({x, y, button, player}, ",") end)
    root:on("touch", function() rootHit = rootHit + 1 end)
    touch(3, 3)
    eq("on handler data", got, "3,3,0,tester")
    eq("a handled event stops at the widget", rootHit, 0)
    front:off("touch", h)
    got = nil
    touch(3, 3)
    check("off removes the handler", got == nil and rootHit == 1, rootHit)
    front:callback(function(_, arg, eventName, scr, x, y) legacy = table.concat({arg, eventName, x, y}, ",") end, "extra")
    touch(4, 3)
    eq("callback(fn, arg) still works", legacy, "extra,touch,4,3")
    root:Destroy()
end

-- layout and UIGrid ---------------------------------------------------------------------------------
do
    local root = scene()
    local panel = gui.Frame(root, 1, 1)
    panel:size(40, 12)
    panel:bordered(true)
    panel:borderSet(panel.Borders.SIMPLE_LINE)
    local fill = gui.Rectangle(panel, 1, 1, 1, 1, 0x222222)
    fill:layout{left = 1, right = 1, top = 2, bottom = 1}
    local corner = gui.Rectangle(panel, 1, 1, 6, 2, 0x444444)
    corner:layout{right = 0, bottom = 0}
    local half = gui.Rectangle(panel, 1, 1, 1, 1, 0x666666)
    half:layout{width = "50%", height = 2, center = true}
    root:draw()
    eq("fill with margins", table.concat({fill:x(), fill:y(), fill:width(), fill:height()}, ","), "3,4,36,7")
    eq("pinned to corner", table.concat({corner:x(), corner:y()}, ","), "34,10")
    eq("percent + center", table.concat({half:x(), half:y(), half:width()}, ","), "11,6,19")
    local grid = gui.UIGrid(root, 1, 15)
    grid:size(30, 10)
    grid:columns(3)
    grid:padding(1, 1)
    grid:rows(2)
    local cells = {}
    for i = 1, 7 do cells[i] = gui.Rectangle(grid, 1, 1, 1, 1, 0x100000 * i) end
    root:draw()
    eq("grid cell 5", table.concat({cells[5]:x(), cells[5]:y(), cells[5]:width(), cells[5]:height()}, ","), "11,3,9,1")
    check("grid hides past rows", not cells[7]:visible() and cells[6]:visible())
    grid:removeChild(cells[1])
    eq("grid gives back size", table.concat({cells[1]:x(), cells[1]:width()}, ","), "1,1")
    root:Destroy()
end

-- moveTo / resizeTo are timed in seconds ----------------------------------------------------------
do
    local root = scene()
    local box = gui.Rectangle(root, 1, 1, 2, 2, 0xff0000)
    box:moveTo(21, 11, 0.5)
    box:resizeTo(6, 4, 0.5)
    local t0 = computer.uptime()
    root:draw()
    local mid
    while box:moveTo() do
        os.sleep(0.05)
        root:draw()
        if not mid and computer.uptime() - t0 >= 0.25 then mid = box:x() end
    end
    local took = computer.uptime() - t0
    eq("moveTo arrives", table.concat({box:x(), box:y(), box:width(), box:height()}, ","), "21,11,6,4")
    check("moveTo takes its time", took >= 0.45 and took <= 0.85, ("%.2f s"):format(took))
    check("moveTo is midway at half time", mid and mid > 5 and mid < 18, mid)
    root:Destroy()
end

-- animate: easing, colours, delay, repeats/yoyo, done events, takeover, cancel/finish ---------------
do
    local root = scene()
    local box = gui.Rectangle(root, 1, 1, 2, 2, 0x000000)
    local function runFor(seconds)
        local t0 = computer.uptime()
        repeat root:draw() os.sleep(0.05) until computer.uptime() - t0 >= seconds
        root:draw()
    end
    local done, events = 0, 0
    box:on("animationDone", function() events = events + 1 end)
    local a = box:animate({x = 41, backgroundColor = 0xff0000}, 1, {easing = "outQuad", onDone = function() done = done + 1 end})
    runFor(0.5)
    -- outQuad at t=0.5 is 0.75 of the way (timing jitter: allow 0.65..0.85)
    check("easing outQuad ahead of linear at half time", box:x() >= 27 and box:x() <= 38, box:x())
    local red = (box:backgroundColor() >> 16) & 0xff
    check("colour blends per channel", red > 0x80 and red < 0xff and box:backgroundColor() & 0xffff == 0, ("%06x"):format(box:backgroundColor()))
    runFor(0.6)
    eq("animation ends on target", box:x() .. "," .. ("%06x"):format(box:backgroundColor()), "41,ff0000")
    check("onDone and animationDone once each", done == 1 and events == 1 and a.done, done .. "/" .. events)

    box:animate({y = 11}, 0.2, {delay = 0.6})
    runFor(0.2)
    eq("delay holds the start", box:y(), 1)
    runFor(0.8)
    eq("delayed animation ran", box:y(), 11)

    local loops = box:animate({x = 1}, 1, {repeats = 2, yoyo = true}) -- 41 -> 1 -> 41 -> 1
    runFor(1.5)
    check("yoyo comes back", box:x() >= 10 and box:x() <= 35, box:x())
    runFor(1.8)
    check("repeats then stops", loops.done and box:x() == 1, box:x())

    box:animate({x = 21, y = 1}, 1)
    local takeover = box:animate({x = 5}, 0.2)
    runFor(0.3)
    check("newer animation takes over a property", box:x() == 5 and box:moveTo() == nil and box:y() < 11, box:x() .. "," .. box:y())
    box:stopAnimations(true)
    eq("finish jumps to the end", box:y(), 1)

    local moving = box:animate({x = 61}, 2)
    runFor(0.3)
    moving:cancel()
    local stopped = box:x()
    runFor(0.2)
    check("cancel stops in place", box:x() == stopped and stopped > 5 and stopped < 61, stopped)

    local chained
    box:animate({x = 1}, 0.1, {onDone = function(w) chained = w:animate({y = 5}, 0.1) end})
    runFor(0.4)
    check("onDone can start the next animation", chained and chained.done and box:y() == 5, box:y())
    root:Destroy()
end

-- errors: a widget whose draw fails shows a red box; onError can take over ----------------------
do
    local root = scene()
    local bad = gui.Rectangle(root, 3, 3, 30, 1, 0x333333)
    bad.draw = function() error("kaput") end
    local fine = gui.Rectangle(root, 3, 5, 4, 1, 0x00ff00)
    root:draw()
    local _, _, bg = proxy.get(3, 3)
    check("failed widget drawn as a red box", bg == 0xcc0000, ("%06x"):format(bg or 0))
    check("red box shows the message", row(3, 3, 30):find("kaput") ~= nil, row(3, 3, 30))
    local _, _, okBg = proxy.get(3, 5)
    eq("other widgets still draw", okBg, 0x00ff00)
    local f = io.open("/tmp/loom.log")
    check("error logged to /tmp/loom.log", f and f:read("a"):find("kaput") ~= nil)
    if f then f:close() end
    local seen = {}
    local old = loom.onError(function(widget, message, during) seen[#seen + 1] = during .. ":" .. tostring(message:match("kaput") or message:match("boom")) return true end)
    root:draw()
    local _, _, bg2 = proxy.get(3, 3)
    check("handler returning true skips the box", bg2 ~= 0xcc0000)
    fine:on("touch", function() error("boom") end)
    touch(4, 5)
    check("event errors reach the handler", seen[1] == "draw:kaput" and seen[2] == "touch:boom", table.concat(seen, " "))
    loom.onError(old)
    root:Destroy()
end

-- loom.run: draws on events and animation, not continuously ---------------------------------------
do
    local root = scene()
    local field = gui.TextInput(root, 2, 2, "x")
    field:size(10, 1)
    local draws = 0
    local draw = root.draw
    root.draw = function(self) draws = draws + 1 return draw(self) end
    local phase, idle, blinking, typed = 1, nil, nil, nil
    local timer = event.timer(2, function()
        if phase == 1 then
            idle, draws, phase = draws, 0, 2
            field:focus("tester")
        elseif phase == 2 then
            blinking, draws, phase = draws, 0, 3
            for i = 1, 5 do computer.pushSignal("key_down", kb, 97, 0, "tester") end
        else
            typed = draws
            loom.stop()
        end
    end, 3)
    loom.run(root, 1)
    event.cancel(timer)
    check("idle: about one draw per interval", idle and idle <= 4, ("%s draws in 2 s"):format(idle))
    check("blinking cursor: a draw per blink (0.5 s)", blinking and blinking >= 3 and blinking <= 7, ("%s draws in 2 s"):format(blinking))
    check("each key draws", typed and typed >= 5, ("%s draws for 5 keys"):format(typed))
    eq("keys reached the field", field:text(), "xaaaaa")
    field:blur()
    root:Destroy()
end

-- Draw budget: a busy screen that does not change costs few GPU calls and no screen copy ------------
do
    local root = scene()
    local window = gui.Window(root, 1, 1, W, H)
    window:openTab("Main")
    local tab = window:tab("Main")
    window:selectTab("Main")
    local list = gui.SortedList(tab, 2, 3, 40, 30, 0x222222)
    local items = {}
    for i = 1, 60 do items[i] = "entry " .. i end
    list:list(items)
    for i = 1, 6 do
        local f = gui.TextInput(tab, 50, 2 + i * 3, "field " .. i)
        f:size(20, 1)
        f:backgroundColor(0x113355)
        gui.TextButton(tab, 75, 2 + i * 3, 10, 1, "[ GO ]", 0x660000)
    end
    for _ = 1, 3 do root:draw() end
    check("busy scene drawn", row(4, 3, 7) ~= "       ", row(4, 3, 20))
    local n, c0, cpu, blits, allocs = 20, calls, 0, byName.bitblt or 0, {}
    for _ = 1, n do
        local m0, t0 = computer.freeMemory(), os.clock()
        root:draw()
        cpu = cpu + os.clock() - t0
        allocs[#allocs + 1] = m0 - computer.freeMemory()
    end
    table.sort(allocs)
    local perDraw = (calls - c0) / n
    check("unchanged frame is not copied to the screen", (byName.bitblt or 0) == blits)
    check("gpu calls per unchanged draw <= 10", perDraw <= 10, perDraw)
    check("cpu per unchanged draw <= 3 ms", cpu / n * 1000 <= 3, ("%.2f ms"):format(cpu / n * 1000))
    check("garbage per unchanged draw <= 32 KiB", allocs[n // 2] <= 32768, allocs[n // 2] .. " B")

    -- A small change redraws and copies only the changed part, and the result matches a whole redraw.
    local function snapshot()
        local cells = {}
        for y = 1, H do
            for x = 1, W do
                local ch, f, b = proxy.get(x, y)
                cells[#cells + 1] = ch .. f .. "/" .. b
            end
        end
        return cells
    end
    local field = tab._childs[#tab._childs - 1]
    field:text("changed")
    local button = tab._childs[#tab._childs]
    button:position(button:x() + 1, button:y()) -- a moved widget damages where it was and where it is
    local c1 = calls
    lastBlit = nil
    root:draw()
    local small = calls - c1
    local area = lastBlit and lastBlit[4] * lastBlit[5] or 0
    check("small change copies only the damaged part", area > 0 and area < W * H / 10, lastBlit and (lastBlit[4] .. "x" .. lastBlit[5]))
    local partial = snapshot()
    root._lastDrawLog = nil
    local c2 = calls
    root:draw()
    local whole = calls - c2
    check("small change replays few calls", small < whole / 3, ("%d calls, %d for a whole redraw"):format(small, whole))
    local full, diff = snapshot(), 0
    for i = 1, #full do if full[i] ~= partial[i] then diff = diff + 1 end end
    check("partial redraw matches a whole redraw", diff == 0, diff .. " cells differ")
    root:Destroy()
end

end, debug.traceback)
if not ok then check("tests ran to the end", false, err) end

local f = io.open("/home/loomtest.txt", "w")
f:write(table.concat(out, "\n"), "\n", failed == 0 and "ALL PASS" or (failed .. " FAILED"), "\n")
f:close()
require("term").clear()
print("loomtest done")
