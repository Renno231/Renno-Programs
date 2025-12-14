# Renno-Programs
This repository houses programs made by Renno231 for OPPM (OpenPrograms Package Manager).

# Projects
## yawl-e
Yet Another Widget Library (Enhanced). An enhanced fork of YAWL, a Widget-based GUI library made by AR2000 that takes advantage of GPU VRAM buffering added in OpenComputers 1.7.6 for more advanced GUIs.
<br><br> To install and use yawl-e follow these instructions:
- install [oppm](https://ocdoc.cil.li/tutorial:program:oppm) and run the following commands (you can also copy and paste them into the terminal with the insert key)
- `oppm register AR2000AR/openComputers_codes`
- `oppm register Renno231/Renno-Programs`
- `oppm -f install yawl-e`

Once installed, yawl-e can be used with `require("yawl-e")` in your programs.
Here's an example of yawl-e in action in another project of mine.

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
