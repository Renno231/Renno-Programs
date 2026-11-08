# Button Widget

The `Button` widget is a subclass of the `Rectangle` widget. It provides additional functionality for creating interactive buttons.

## Table of Contents

- [Constructor](#constructor)
- [Methods](#methods)

## Constructor

The `Button` widget is created using the `new` method.

```lua
---@param parent Frame
---@param x number
---@param y number
---@param width number
---@param height number
---@param backgroundColor number

local Button = require('libClass2')(Rectangle)
```

### Parameters

- `parent`: The parent frame of the button.
- `x`: The x-coordinate of the button's top-left corner.
- `y`: The y-coordinate of the button's top-left corner.
- `width`: The width of the button.
- `height`: The height of the button.
- `backgroundColor`: The background color of the button.

## Methods

### defaultCallback

The `defaultCallback` method is called when the button is clicked.

```lua
function Button:defaultCallback(_, eventName, uuid, x, y, button, playerName)
```

### activate

The `activate` method sets or gets the activation state of the button.

```lua
function Button:activate(state)
```

### resetTime

The `resetTime` method sets or gets the time after which the button should reset.

```lua
function Button:resetTime(time)
```
### shouldReset

The `shouldReset` method sets or gets whether the button should reset after a certain time.

```lua
function Button:shouldReset(should)
```
### draw

The `draw` method draws the button on the screen.

```lua
function Button:draw()
```