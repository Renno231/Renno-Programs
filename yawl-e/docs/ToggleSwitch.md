# ToggleSwitch Widget

The `ToggleSwitch` widget is a custom UI component in Lua, designed to provide a toggle switch functionality. It extends from the `Widget` class.

## Class Definition

```lua
---@class ToggleSwitch:Widget
---@field parent Widget
---@field private _speed number
---@field private _slider table
---@operator call:ToggleSwitch
---@overload fun(parent:Frame,x:number,y:number,width:number,height:number,backgroundColor:number|nil,foregroundColor:number|nil):ToggleSwitch

local ToggleSwitch = class(Widget)
```

## Constructor

The constructor for the `ToggleSwitch` widget is defined as follows:

```lua
function ToggleSwitch:new(parent, x, y, width, height, backgroundColor, foregroundColor, activeBG)
```

### Parameters

- `parent`: The parent frame for the widget.
- `x`: The x-coordinate for the widget.
- `y`: The y-coordinate for the widget.
- `width`: The width of the widget.
- `height`: The height of the widget.
- `backgroundColor`: The background color of the widget. Optional.
- `foregroundColor`: The foreground color of the widget. Optional.
- `activeBG`: The background color when the widget is active. Optional.

## Methods

### defaultCallback

The `defaultCallback` method is used to handle touch events on the widget.

```lua
function ToggleSwitch:defaultCallback(_, eventName)
```

### Parameters

- `_`: Unused parameter.
- `eventName`: The name of the event.

### Behavior

If the event name is "touch", the toggle switch will toggle its state and return true.