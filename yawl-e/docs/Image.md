
The `Image` widget is a subclass of the `Widget` class. It provides functionality for creating an image.
## Table of Contents

- [Constructor](#constructor)
- [Methods](#methods)

## Constructor

The `Image` widget is created using the `new` method.
### Parameters

- `parent`: The parent frame of the image.
- `x`: The x-coordinate of the image's top-left corner.
- `y`: The y-coordinate of the image's top-left corner.
- `img`: The image file or a string representing the image.

## Methods

### width

The `width` method gets the width of the image.

```lua
function Image:width(value)
```

### height

The `height` method gets the height of the image.

```lua
function Image:height(value)
```

### imageData

The `imageData` method sets or gets the image data of the image.

```lua
function Image:imageData(value)
```

#### Parameters

- `value`: (Optional) The new image data to set.

### draw

The `draw` method draws the image on the screen.

```lua
function Image:draw()
```

