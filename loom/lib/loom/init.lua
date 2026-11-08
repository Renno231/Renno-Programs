---@class Position
---@field x number
---@field y number

---@class Size
---@field width number
---@field height number

local run = require('loom.run')
---@class loomlib
local loom = {
    widget = require('loom.widget'),
    util = require('loom.util'),
    ---Draw a root frame whenever something may have changed, until `loom.stop()`. See loom/run.lua.
    run = run.run,
    stop = run.stop,
    ---Ask `loom.run` for a redraw within `delay` seconds (default now).
    invalidate = run.request,
    ---Handle widget errors yourself: `loom.onError(function(widget, message, during) end)`. See loom/run.lua.
    onError = run.onError,
    ---Handle keys no widget used: `loom.onKey(function(char, code, player) end)`. See loom/input.lua.
    onKey = require('loom.input').onKey,
    ---The widget with keyboard focus, or nil.
    focused = require('loom.input').focused,
}

-- ImageFile is only needed by programs that load images; load it on first use.
return setmetatable(loom, {__index = function(t, key)
    if key == "ImageFile" then
        local ImageFile = require("loom.ImageFile")
        rawset(t, key, ImageFile)
        return ImageFile
    end
end})
