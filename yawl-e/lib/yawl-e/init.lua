---@class Position
---@field x number
---@field y number

---@class Size
---@field width number
---@field height number

---@class yaowbgllib
local yawl = {
    widget = require('yawl-e.widget'),
    util = require('yawl-e.util')
}

-- ImageFile is only needed by programs that load images; load it on first use.
return setmetatable(yawl, {__index = function(t, key)
    if key == "ImageFile" then
        local ImageFile = require("yawl-e.ImageFile")
        rawset(t, key, ImageFile)
        return ImageFile
    end
end})
