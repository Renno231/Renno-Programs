# Keyboard navigation

One widget at a time has keyboard focus. Buttons, TextButtons, ToggleSwitches, SliderBars,
SortedLists, DropdownLists and TextInputs can take focus; mark any other widget with
`widget:focusable(true)`. Only widgets drawn in the latest frame can take focus, so hidden tabs and
removed widgets drop out on their own.

`loom.run` listens for keys while it runs. Without it, keys are listened for while a widget has focus.

## Keys

| Key | Does |
| --- | --- |
| Arrows | focus the nearest widget in that direction (distance between centres: along + 3 × across, rows counted double) |
| Tab / Shift+Tab | next / previous widget in reading order |
| Enter / Space | the same as a touch on the widget: callbacks get `eventName == "touch"` |
| Escape | clear focus (when no `onKey` handler is set) |

The focused widget gets the keys first:

- **ToggleSwitch**: Enter/Space flip it, the same as a touch.
- **SliderBar**: Left/Right move the value by `slider:step()` (default: one cell's worth).
- **SortedList**: Up/Down move a cursor row and scroll with it; Enter/Space select that row (or
  deselect it if it's the only one selected). At the top or bottom row, the arrow moves focus out of
  the list.
- **DropdownList**: Enter/Space open it and focus its list; Enter on a row picks it, closes the list and
  gives focus back to the dropdown.
- **TextInput**: takes typing, digits included; Escape blurs it.

A focused widget gets white brackets just outside it, on its parent's background, so the widget
keeps its look: `[` and `]` beside a one-row widget, `┌│└` and `┐│┘` beside a taller one. A focused
SortedList also shows its cursor row in a lighter colour with a white `▌`. Widgets inside a
disabled frame can't take focus (a dialog can disable the frame behind it).

## API

```lua
widget:focus(player)      -- give it focus; with `player`, only that player's keys count
widget:blur()
widget:focused()          -- true if it has focus
widget:focusable(value)   -- get/set whether it can take focus
loom.focused()            -- the focused widget, or nil
loom.onKey(function(char, code, player) ... end) -- keys no widget used; returns the old handler
```

Focus stays across redraws while the same widget is still drawn. A touch on a focusable widget
focuses it; a touch anywhere else clears focus.

A widget class can handle its own keys with `Widget:_key(char, code, ctrl, player)`: return true if
it used the key. To draw its own focus marker, override `Widget:_drawFocus()`; Frame calls it after
drawing its children.
