# Frame Widget

The `Frame` widget is a subclass of the `Widget` class. It provides functionality for creating a frame.

## Table of Contents

- [Constructor](#constructor)
- [Methods](#methods)
## Constructor

The `Frame` widget is created using the `new` method.

```lua
function Frame:new(parentFrame, x, y)
```

### Parameters

- `parentFrame`: The parent frame of the new frame.
- `x`: The x-coordinate of the new frame's top-left corner.
- `y`: The y-coordinate of the new frame's top-left corner.

## Methods

Based on the provided code, it seems like the `Frame` widget has several private fields and methods. However, without the full code, it's hard to document all of them. Here are some that can be inferred from the provided code:

### _touchHandler

The `_touchHandler` method handles touch events.

```lua
function Frame:_touchHandler(...)
```

### propagateEvent

The `propagateEvent` method propagates events to child widgets.

```lua
function Frame:propagateEvent(...)
```