# Text Label Widget

The `TextLabel` widget is a subclass of the `Widget` class. It provides functionality for creating a simple one-line text label.

## Table of Contents

- [Constructor](#constructor)
- [Methods](#methods)
## Constructor

The `TextLabel` widget is created using the `new` method.

```lua
function TextLabel:new(parent, x, y, text, foregroundColor)
```

### Parameters

- `parent`: The parent frame of the text label.
- `x`: The x-coordinate of the text label's top-left corner.
- `y`: The y-coordinate of the text label's top-left corner.
- `text`: The text to display.
- `foregroundColor`: (Optional) The color of the text.

## Methods

### text

The `text` method sets or gets the text of the text label.

```lua
function TextLabel:text(value)
```

#### Parameters

- `value`: (Optional) The new text to set.

### height

The `height` method sets or gets the height of the text label.

```lua
function TextLabel:height(value)
```

#### Parameters

- `value`: (Optional) The new height to set.

### autoWidth

The `autoWidth` method sets or gets whether the width of the text label should automatically adjust to the length of the text.

```lua
function TextLabel:autoWidth(value)
```

#### Parameters

- `value`: (Optional) Whether to enable auto width.