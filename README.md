# Renno-Programs
This repository houses programs made by Renno231 for OPPM (OpenPrograms Package Manager).

# Projects
## Loom
A widget-based GUI library for OpenComputers. It started as YAWL-E, an enhanced fork of AR2000's YAWL, and draws every widget into one GPU VRAM buffer (OpenComputers 1.7.6+) that reaches the screen only when the frame changes.
<br><br> To install and use Loom follow these instructions:
- install [oppm](https://ocdoc.cil.li/tutorial:program:oppm) and run the following command (you can also copy and paste it into the terminal with the insert key)
- `oppm register Renno231/Renno-Programs`
- `oppm -f install loom`

Once installed, Loom can be used with `require("loom")` in your programs. `require("yawl-e")` still works for now and returns Loom.

```lua
local loom = require("loom")
local gui = loom.widget
local root = gui.Frame()
root:backgroundColor(0x000000)
local name = gui.TextInput(root, 1, 1, "")
name:layout{left = 2, right = 2, top = 1, height = 1} -- stays 2 cells from each side as the screen resizes
name:placeholder("your name")
name:on("submit", function(self, text) loom.stop() end)
local quit = gui.TextButton(root, 1, 1, 8, 1, "[ QUIT ]", 0xffffff)
quit:layout{right = 1, bottom = 0}
quit:on("touch", function() loom.stop() end)
loom.run(root) -- redraws after events and animations only; returns after loom.stop()
root:Destroy()
```

- `loom.run(root, interval)` draws when something may have changed: after each signal, while a widget animates, and at least every `interval` seconds (default 0.5). Call `loom.invalidate()` after changing widgets from a timer to redraw at once.
- `widget:on(event, handler)` / `widget:off(event, handler)`: handlers get `(self, ...)` with the event data, for screen events `(self, screen, x, y, button, player)`. Return true to stop the event there. `callback` still works.
- `widget:layout{left, right, top, bottom, width, height, center}` places a widget relative to its parent on each draw; values are cells or `"N%"`. `UIGrid` lays its children out in columns.
- `widget:animate(to, seconds, options)` animates any numeric property, colours included, e.g. `panel:animate({x = 10, backgroundColor = 0x003366}, 0.4, {easing = "outBack"})`. Options: `easing` (linear, in/out/inOut Quad and Cubic, outBack, outElastic, in/outBounce, or a function), `delay`, `repeats` (`true` = forever), `yoyo`, `onDone`. It returns a handle with `:cancel()` and `:finish()`; the widget gets an `"animationDone"` event. `moveTo(x, y, seconds)` and `resizeTo(width, height, seconds)` are shortcuts (`tweenPosition`/`tweenSize` still work).
- A widget whose draw errors shows as a red box with the message, and the error goes to `/tmp/loom.log`; errors in event handlers are logged too. `loom.onError(function(widget, message, during) end)` handles them yourself (return true to skip the red box).
- `TextInput` has focus with Tab/Shift+Tab, Enter to submit, word jumps, paste, placeholder, masking and length limits; see [docs/TextInput.md](loom/docs/TextInput.md).
- Tests run on Ocelot Harness: `powershell loom/test/run.ps1`.
Here's an example of Loom in action in another project of mine.

![java_L73glKpY8l-ezgif com-video-to-gif-converter](https://github.com/Renno231/Renno-Programs/assets/75190549/d81f54f3-d4f1-42af-aa90-b245ecd3b330)

## TNET
Transport Network Library. TNET acts as a TCP-like wrapper over the standard UDP-like OpenComputers modems. It abstracts away the limitations of component signals to provide reliable, stateful connections. It includes packet fragmentation which automatically breaks down large payloads (files, serialized tables) into packets that fit within network MTU limits and cleanly restitches them on the receiving end. It's recommended to use my highly optimized LZSS library for traffic compression for larger data uses like FTP. It includes an API library that is an application level/layer implementation over TNET.
Basic example usage of TNET:
```lua
local tnet = require("tnet")

-- Server
tnet.listen(123, function(conn)
    conn:expect("data", function(c, msg)
        print("Received:", msg)
        c:send("ACK")
    end)
end)

-- Client
local conn = tnet.connect(server_addr, 123)
conn:send("Hello World")
```
Basic example usage of API:
```lua
--SERVER SIDE
local api = require("api")

local myLib = {
    greet = function(name) return "Hello, " .. name end
}

-- Expose 'myLib' on port 1000
api.expose("greeting_service", myLib, 1000)
```
```lua
--CLIENT SIDE
local api = require("api")

-- Connect to the service
local proxy = api.connect("greeting_service", 1000, server_address)

-- Call it like a local function
local response = proxy.greet("User") 
print(response) -- Output: "Hello, User"
```

## ECC
Elliptic Curve Cryptography library OpenComputers port for network security protocols like ECDH (Elliptic-curve Diffie–Hellman)
<br><br> To install and use ECC follow these instructions:
- install [oppm](https://ocdoc.cil.li/tutorial:program:oppm) and run the following commands (you can also copy and paste them into the terminal with the insert key)
- `oppm register Renno231/Renno-Programs`
- `oppm -f install ecc`

## Nodemap
A nodemap utility for pathfinding that can create, save, and import maps of nodes (x,y,z,name).

## Ebake
A binfile utility using a mini-lzss decompressor to create bios files. Usage: ebake ChunkNameHere < /path/to/input/file.lua > /path/to/bios.lua Credit: lunar_sam.

## LZSS
Lossless data compression library. Credit: unknown
