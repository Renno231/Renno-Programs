local loom = {
    --[[Widget       = require('loom.widget.Widget'),
    Rectangle    = require('loom.widget.Rectangle'),
    Frame        = require('loom.widget.Frame'),
    Text         = require("loom.widget.Text"),
    Image        = require("loom.widget.Image"),
    TextInput    = require("loom.widget.TextInput"),
    LinkedWidget = require("loom.widget.LinkedWidget"),
    WidgetList   = require("loom.widget.WidgetList"),
    Border       = require("loom.widget.Border"),
    Histogram    = require("loom.widget.Histogram"),
    ToggleSwitch = require("loom.widget.ToggleSwitch"),
    SliderBar    = require("loom.widget.SliderBar"),
    ProgressBar  = require("loom.widget.ProgressBar"),
    SortedList   = require("loom.widget.SortedList"),
    Button       = require("loom.widget.Button"),
    DropdownList = require("loom.widget.DropdownList")]]
}
setmetatable(loom,{
    __index = function(table, index, value)
        local succ, lib = pcall(require, "loom.widget."..index)
        if not succ then
            if require"component".isAvailable("ocelot") then
                require"component".ocelot.log(lib)
                return
            end
        end
        rawset(lib, "Class", index)
        if not rawget(loom, index) then rawset(loom, index, lib) end
        return lib
    end
})
--[=[
for class, object in pairs (loom) do
    --[[
        local object = require("loom.widget."..object)
        loom[class] = object
        object.Class = class 
    ]]
    object.Class = class
end]=]

--could potentially make metamethod that loads these as needed instead of all at once (reduces memory cost when not all things are utilized)

return loom
