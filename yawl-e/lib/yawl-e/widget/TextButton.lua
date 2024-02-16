--text class object with a :value() and defaultCallback for touch
local Text = require("yawl-e.widget.Text")
local TextButton = require("libClass2")(Text)
local unicode = require("unicode")

function TextButton:new(parent, x, y, width, height, text, foregroundColor)
    checkArg(1, parent, 'table')
    checkArg(2, x, 'number', 'table')
    checkArg(3, y, 'number', 'nil')
    checkArg(4, text, 'string')
    checkArg(5, foregroundColor, 'number', 'nil')
    checkArg(4, width, 'number', 'nil')
    checkArg(5, height, 'number')
    if (type(x) == "table") then checkArg(3, y, 'nil') else checkArg(3, y, 'number') end
    local o = self.parent(parent, x, y, text, foregroundColor)
    setmetatable(o, {__index = self})
    ---@cast o Text
    o:size(width or unicode.len(self._parsedText and self._parsedText[1] or text or " "), height)
    o:textHorizontalAlignment("center")
    o:textVerticalAlignment("center")
    o:textOffset("center")
    
    return o
end

function TextButton:width(width)
    checkArg(1, width, 'number', 'nil')
    local oldValue = self._size.width
    if (width) then 
        self._size.width = width
        self:wrapWidth(width)
        self:_parse()
    end
    return oldValue
end
-- function TextButton:defaultCallback()

-- end

return TextButton