# Dropdown List Widgetw

The `DropdownList` widget is a subclass of the `Widget` class. It provides functionality for creating a dropdown list.

## Table of Contents

- [Constructor](#constructor)
- [Methods](#methods)

## Constructor

The `DropdownList` widget is created using the `new` method.

```lua
function DropdownList:new(parent, x, y, width, height, backgroundColor, listobj)
```

### Parameters

- `parent`: The parent frame of the dropdown list.
- `x`: The x-coordinate of the dropdown list's top-left corner.
- `y`: The y-coordinate of the dropdown list's top-left corner.
- `width`: The width of the dropdown list.
- `height`: The height of the dropdown list.
- `backgroundColor`: The background color of the dropdown list.
- `listobj`: The list object to be used for the dropdown list.

## Methods

### value

The `value` method sets or gets the value of the dropdown list.

```lua
function DropdownList:value(val, state)
```