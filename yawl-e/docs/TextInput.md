# TextInput Widget

The `TextInput` widget is a custom UI component in Lua, designed to provide a text input functionality. It extends from the `Text` class.

## Class Definition

```lua
---@class TextInput:Text
---@field private _listeners.keyDownEvent number
---@field private _listeners.touchEvent number
---@operator call:TextInput
---@overload fun(parent:Frame,x:number,y:number,text:string,foregroundColor:number):TextInput
local TextInput = class(Text)
```

## Constructor

The constructor for the `TextInput` widget is defined as follows:

```lua
function TextInput:new(parent, x, y, text, foregroundColor)
```

### Parameters

- `parent`: The parent frame for the widget.
- `x`: The x-coordinate for the widget.
- `y`: The y-coordinate for the widget.
- `text`: The initial text of the widget.
- `foregroundColor`: The foreground color of the widget.

## Methods

### _onKeyDown

The `_onKeyDown` method is used to handle key down events on the widget.

```lua
function TextInput:_onKeyDown(eventName, component, char, key, player)
```

### Parameters

- `eventName`: The name of the event.
- `component`: The component that triggered the event.
- `char`: The character code of the key pressed.
- `key`: The key code of the key pressed.
- `player`: The player who pressed the key.

### Behavior

This method handles the following keys:

- Backspace & Delete: Removes a character from the text.
- Arrow keys: Moves the cursor in the text.

## TODO

The following features are planned to be added in the future:

- Listener for paste event
- Auto-scroll and auto-size in `_onKeyDown`
- Fix/finish behavior in `_onKeyDown`