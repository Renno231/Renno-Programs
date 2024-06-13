# UIGrid Widget

The `UIGrid` widget is a custom UI component in Lua, designed to provide a grid layout functionality. It extends from the `Frame` class.

## Class Definition

```lua
---@class UIGrid:Frame
---@field private _childData table
local UIGrid = class(Frame)
```
## Constructor

The constructor for the `UIGrid` widget is not explicitly defined in the provided code. It should be similar to the `Frame` widget's constructor.

## Methods

### addChild

The `addChild` method is used to add a child widget to the grid.

```lua
function UIGrid:addChild(containerChild)
```

### Parameters

- `containerChild`: The child widget to be added.

### removeChild

The `removeChild` method is used to remove a child widget from the grid.

```lua
function UIGrid:removeChild(child)
```
### Parameters

- `child`: The child widget to be removed.

### columns

The `columns` method is used to set the number of columns in the grid.

```lua
function UIGrid:columns(num)
```

### Parameters

- `num`: The number of columns.

### columnPadding

The `columnPadding` method is used to set the padding between columns.

```lua
function UIGrid:columnPadding(num)
```

### Parameters

- `num`: The padding between columns.

### rowPadding

The `rowPadding` method is used to set the padding between rows.

```lua
function UIGrid:rowPadding(num)
```

### Parameters

- `num`: The padding between rows.

### padding

The `padding` method is used to set the padding in the grid.

```lua
function UIGrid:padding(x, y)
```

### Parameters

- `x`: The horizontal padding.
- `y`: The vertical padding.

### rows

The `rows` method is used to set the number of rows in the grid.

```lua
function UIGrid:rows(num)
```

### Parameters

- `num`: The number of rows.

### cellWidth

The `cellWidth` method is used to set the width of the cells in the grid.

```lua
function UIGrid:cellWidth(num)
```

### Parameters

- `num`: The width of the cells.

## TODO

The following features are planned to be added in the future:

- Finish grid logic
- Add cell height functionality
- Add scroll functionality
- Add autofit functionality