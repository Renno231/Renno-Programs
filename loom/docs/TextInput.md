# TextInput Widget

An editable text field. Touch it, or Tab to it, to type. Single-line fields scroll sideways to keep the cursor in view; fields taller than one line are multiline and scroll both ways.

```lua
local name = gui.TextInput(root, 10, 5, "", 0xffffff)
name:size(20, 1)
name:backgroundColor(0x113355)
name:placeholder("your name")
name:on("submit", function(self, text) print("hello " .. text) end)
```

## Constructor

```lua
gui.TextInput(parent, x, y, text, foregroundColor)
```

`text` and `foregroundColor` are optional.

## Keys

| Key | Action |
|---|---|
| Left / Right | Move one character (Ctrl: one word) |
| Up / Down | Move one line in a multiline field, keeping the column across short lines |
| Home / End | Start / end of the line (Ctrl, or a single-line field: of the text) |
| Backspace / Delete | Delete one character (Ctrl: one word) |
| Enter | Submit. In a multiline field Enter inserts a newline and Ctrl+Enter submits |
| Tab / Shift+Tab | Move to the next / previous field on screen, in reading order |
| Escape | Leave the field |

Pasting (the clipboard signal) inserts the text at the cursor; a single-line field drops a trailing newline and turns other newlines into spaces. Touching the field puts the cursor under the touch; right-clicking clears it. Touching anywhere else leaves the field. Only the player who focused the field can type in it.

## Events

Passed to `callback` and to `on` handlers:

- `"submit"` (text): Enter was pressed.
- `"valueChanged"` (old, new): the text changed.
- `"cursorChanged"` (index, x, y)
- `"focus"`, `"blur"`

## Methods

- `text(...)`: get, or set (arguments joined with spaces; the cursor moves to the end). Returns the old text.
- `insert(str)`: insert at the cursor.
- `submit()`: as if Enter was pressed.
- `focus(player?)`, `blur()`, `focused()`
- `cursor(index?)`: the cursor as a text index, 0 = before the first character.
- `cursorXY(x?, y?)`: the cursor as column and line.
- `clearOnEnter(bool?)`: after submit, clear the field and keep typing (chat style). Otherwise submit leaves the field. Default false.
- `multilines(bool?)`: default true when the field is taller than one line (three with a border).
- `maxLength(n|false?)`: longest text accepted.
- `placeholder(text|false?, color?)`: shown dimmed while the field is empty and not focused.
- `mask(char|false?)`: show every character as `char`, for passwords. `text()` still returns the typed text.
- `cursorBlinks(bool?)`, `cursorBlinkTime(seconds?)`: default blinking, 0.5 s.
