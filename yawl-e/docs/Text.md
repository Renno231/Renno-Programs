# Text

The `Text` widget is a subclass of the `Widget` class. It provides functionality for creating a text.

## Table of Contents

- [Constructor](#constructor)
- [Methods](#methods)

## Constructor

The `Text` widget is created using the `new` method.

```lua
function Text:new(parent, x, y, text, foregroundColor)
```

### Parameters

- `parent`: The parent frame of the text.
- `x`: The x-coordinate of the text's top-left corner.
- `y`: The y-coordinate of the text's top-left corner.
- `text`: The text to display.
- `foregroundColor`: (Optional) The color of the text.

## Methods

### text

The `text` method sets or gets the text of the text widget.

```lua
function Text:text(value)
```

#### Parameters

- `value`: (Optional) The new text to set.

### textOffset

The `textOffset` method sets the offset of the text.

```lua
function Text:textOffset(value)
```

### textHorizontalAlignment

The `textHorizontalAlignment` method sets the horizontal alignment of the text.

```lua
function Text:textHorizontalAlignment(value)
```

### textVerticalAlignment

The `textVerticalAlignment` method sets the vertical alignment of the text.

```lua
function Text:textVerticalAlignment(value)
```

### foregroundColor

The `foregroundColor` method sets or gets the color of the text.

```lua
function Text:foregroundColor(value)
```

#### Parameters

- `value`: (Optional) The new color to set.