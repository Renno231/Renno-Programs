# Window Widget

The `Window` widget is a custom UI component in Lua, designed to provide a window functionality with multiple tabs. It extends from the `ScrollFrame` class.

## Class Definition

```lua
---@class Window:ScrollFrame
---@field private _tabs table
---@field private _tabsSorted table
---@field private _tabCount number
---@field private _borderoverride boolean
---@field private _hitboxTop table
---@field private _hitboxBottom table
local Window = class(ScrollFrame)
```

## Constructor

The constructor for the `Window` widget is defined as follows:

```lua
function Window:new(parentFrame, x, y, width, height)
```

### Parameters

- `parentFrame`: The parent frame for the widget.
- `x`: The x-coordinate for the widget.
- `y`: The y-coordinate for the widget.
- `width`: The width of the widget.
- `height`: The height of the widget.

## Methods

### propagateEvent

The `propagateEvent` method is used to propagate events to the widget.

```lua
function Window:propagateEvent(eName, screenAddress, x, y, ...)
```

### Parameters

- `eName`: The name of the event.
- `screenAddress`: The screen address of the event.
- `x`: The x-coordinate of the event.
- `y`: The y-coordinate of the event.
- `...`: Additional parameters for the event.

### tab

The `tab` method is used to retrieve a tab if it exists.

```lua
function Window:tab(tabName)
```

### Parameters

- `tabName`: The name of the tab.

### clearChildren

The `clearChildren` method is used to clear all children of the widget.

```lua
function Window:clearChildren()
```

### removeTab

The `removeTab` method is used to remove a tab from the window.

```lua
function Window:removeTab(name)
```

### Parameters

- `name`: The name of the tab to be removed.

### renameTab

The `renameTab` method is used to rename a tab in the window. The method body is not provided in the given code.

```lua
function Window:renameTab(name, newname)
```

### Parameters

- `name`: The current name of the tab.
- `newname`: The new name for the tab.

### selectTab

The `selectTab` method is used to select a tab in the window.

```lua
function Window:selectTab(tabname, state)
```

### Parameters

- `tabname`: The name of the tab to be selected.
- `state`: The state of the tab.

### _sortTabs

The `_sortTabs` method is used to sort the tabs in the window based on the last selected time.

```lua
function Window:_sortTabs()
```

### defaultCallback

The `defaultCallback` method is used to handle default callbacks for the window.

```lua
function Window:defaultCallback(_, eventName, uuid, x, y, button, playerName)
```

### Parameters

- `_`: Not used.
- `eventName`: The name of the event.
- `uuid`: The UUID of the event.
- `x`: The x-coordinate of the event.
- `y`: The y-coordinate of the event.
- `button`: The button of the event.
- `playerName`: The name of the player who triggered the event.

### Behavior

This widget provides a window with multiple tabs. Each tab is a `Tab` object which contains a `_childs` table for storing child widgets. The `Window` widget overrides the `clearChildren` method to clear all children of the selected tab.