# Rectangle

The `Rectangle` widget is a subclass of the `Widget` class. It provides functionality for creating a rectangle.

## Table of Contents

- [Constructor](#constructor)
- [Methods](#methods)
## Constructor

The `Rectangle` widget is created using the `new` method.

```lua
function Rectangle:new(parent, x, y, width, height, backgroundColor)
```

### Parameters

- `parent`: The parent frame of the rectangle.
- `x`: The x-coordinate of the rectangle's top-left corner.
- `y`: The y-coordinate of the rectangle's top-left corner.
- `width`: The width of the rectangle.
- `height`: The height of the rectangle.
- `backgroundColor`: (Optional) The background color of the rectangle.

## Methods

### draw

The `draw` method draws the rectangle on the screen.


```lua
function Rectangle:draw()
```