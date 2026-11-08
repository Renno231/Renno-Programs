# Border Widget

The `Border` widget is a subclass of the `Frame` widget. It provides additional functionality for creating a border around a frame.

## Table of Contents

- [Constructor](#constructor)
- [Methods](#methods)

## Constructor

The `Border` widget is created using the `new` method.

```lua
---@param parent Frame
---@param x number
---@param y number
---@param borderset? string
function Border:new(parent, x, y, borderset)
```

### Parameters

- `parent`: The parent frame of the border.
- `x`: The x-coordinate of the border's top-left corner.
- `y`: The y-coordinate of the border's top-left corner.
- `borderset`: (Optional) A string representing the set of characters to use for the border.

## Methods

### autoFit

The `autoFit` method sets whether the border should automatically fit its width and height to its content.

```lua
---@param value? boolean
---@return boolean
function Border:autoFit(widthval, heightval)
```

#### Parameters

- `widthval`: (Optional) A boolean value indicating whether the border should automatically fit its width to its content.
- `heightval`: (Optional) A boolean value indicating whether the border should automatically fit its height to its content.

### draw

The `draw` method draws the border on the screen.

```lua
function Border:draw()
```


This method does not take any parameters.

