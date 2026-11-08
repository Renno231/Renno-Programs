# Histogram Widget

The `Histogram` widget is a subclass of the `Widget` class. It provides functionality for creating a histogram.

## Table of Contents

- [Constructor](#constructor)
- [Methods](#methods)
## Constructor

The `Histogram` widget is created using the `new` method.

```lua
function Histogram:new(parent, x, y, maxColumns)
```

### Parameters

- `parent`: The parent frame of the histogram.
- `x`: The x-coordinate of the histogram's top-left corner.
- `y`: The y-coordinate of the histogram's top-left corner.
- `maxColumns`: (Optional) The maximum number of columns in the histogram.

## Methods

### insert

The `insert` method inserts a value at the end of the histogram.

```lua
function Histogram:insert(value)
```

#### Parameters

- `value`: The value to insert.

### set

The `set` method overrides the value at a specific index in the histogram.

```lua
function Histogram:set(index, value)
```

#### Parameters

- `index`: The index at which to override the value.
- `value`: The new value.

### adjust

The `adjust` method changes an existing value in the histogram.

```lua
function Histogram:adjust(value, index)
```