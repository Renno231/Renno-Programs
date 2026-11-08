# Progress Bar

The `ProgressBar` widget is a subclass of the `Widget` class. It provides functionality for creating a progress bar.
## Table of Contents

- [Constructor](#constructor)
- [Methods](#methods)
## Constructor

The `ProgressBar` widget is created using the `new` method.

```lua
function ProgressBar:new(parent, x, y, width, height, backgroundColor, foregroundColor)
```

### Parameters

- `parent`: The parent frame of the progress bar.
- `x`: The x-coordinate of the progress bar's top-left corner.
- `y`: The y-coordinate of the progress bar's top-left corner.
- `width`: The width of the progress bar.
- `height`: The height of the progress bar.
- `backgroundColor`: (Optional) The background color of the progress bar.
- `foregroundColor`: (Optional) The foreground color of the progress bar.

## Methods

### value

The `value` method sets or gets the value of the progress bar.

```lua
function ProgressBar:value(value)
```

#### Parameters

- `value`: (Optional) The new value to set.

### fillChar

The `fillChar` method sets or gets the fill character of the progress bar.

```lua
function ProgressBar:fillChar(value)
```

#### Parameters

- `value`: (Optional) The new fill character to set.

### fillBackgroundColor

The `fillBackgroundColor` method sets or gets the fill background color of the progress bar.

```lua
function ProgressBar:fillBackgroundColor(value)
```