local yawle = {
    Widget       = require('yawl-e.widget.Widget'),
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
    Button       = require("yawl-e.widget.Button")
}

for class, object in pairs (yawle) do
    object.Class = class
end

return yawle
