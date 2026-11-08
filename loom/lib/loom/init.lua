---@class Position
---@field x number
---@field y number

---@class Size
---@field width number
---@field height number

---@class yaowbgllib
local loom = {
    widget = require('loom.widget'),
    util = require('loom.util')
}

-- ImageFile is only needed by programs that load images; load it on first use.
return setmetatable(loom, {__index = function(t, key)
    if key == "ImageFile" then
        local ImageFile = require("loom.ImageFile")
        rawset(t, key, ImageFile)
        return ImageFile
    end
end})
