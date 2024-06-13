# SortedList Widget

The `SortedList` widget is a custom UI component in Lua, designed to provide a sorted list functionality. It extends from the `Widget` class.

## Class Definition

```lua
---@class SortedList:Widget
---@field private _size Size
---@operator call:SortedList
---@overload fun(parent:Frame,x:number,y:number,width:number,height:number,backgroundColor:number)
local SortedList = require("libClass2")(Widget)
```

## Constructor

The constructor for the `SortedList` widget is defined as follows:

```lua
function SortedList:new(parent, x, y, width, height, backgroundColor)
```

### Parameters

- `parent`: The parent frame for the widget.
- `x`: The x-coordinate for the widget.
- `y`: The y-coordinate for the widget.
- `width`: The width of the widget.
- `height`: The height of the widget.
- `backgroundColor`: The background color of the widget. Optional.

## Methods

### maximumSelectedValues

The `maximumSelectedValues` method is used to get or set the maximum number of selectable values.

```lua
function SortedList:maximumSelectedValues(value)
```

### Parameters

- `value`: The maximum number of selectable values. Optional.

### select

The `select` method is used to get or set the selection state of an item.

```lua
function SortedList:select(index, state)
```

### Parameters

- `index`: The index of the item.
- `state`: The selection state of the item. Optional.

### value

The `value` method is used to get or set the value of an item.

```lua
function SortedList:value(index, newval)
```

### Parameters

- `index`: The index of the item.
- `newval`: The new value of the item. Optional.