local yawle = {
    --[[Widget       = require('yawl-e.widget.Widget'),
    Rectangle    = require('yawl-e.widget.Rectangle'),
    Frame        = require('yawl-e.widget.Frame'),
    Text         = require("yawl-e.widget.Text"),
    Image        = require("yawl-e.widget.Image"),
    TextInput    = require("yawl-e.widget.TextInput"),
    LinkedWidget = require("yawl-e.widget.LinkedWidget"),
    WidgetList   = require("yawl-e.widget.WidgetList"),
    Border       = require("yawl-e.widget.Border"),
    Histogram    = require("yawl-e.widget.Histogram"),
    ToggleSwitch = require("yawl-e.widget.ToggleSwitch"),
    SliderBar    = require("yawl-e.widget.SliderBar"),
    ProgressBar  = require("yawl-e.widget.ProgressBar"),
    SortedList   = require("yawl-e.widget.SortedList"),
    Button       = require("yawl-e.widget.Button"),
    DropdownList = require("yawl-e.widget.DropdownList")]]
}
setmetatable(yawle,{
    __index = function(table, index, value)
        local lib = require("yawl-e.widget."..index)
        if not lib.Class then lib.Class = index end
        if not rawget(yawle, index) then rawset(yawle, index, lib) end
        return lib
    end
})
--[=[
for class, object in pairs (yawle) do
    --[[
        local object = require("yawl-e.widget."..object)
        yawle[class] = object
        object.Class = class 
    ]]
    object.Class = class
end]=]

--could potentially make metamethod that loads these as needed instead of all at once (reduces memory cost when not all things are utilized)

return yawle
