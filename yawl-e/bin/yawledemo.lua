local event = require"event"
local run = true
event.listen("interrupted", function()
    run = false
    for i,_ in pairs (package.loaded) do if i:match("yawl") then package.loaded[i] = nil end end
    package.loaded.ecc = nil
    return false
end)

local yawl = require("yawl-e")
-- local ecc = require("ecc") --105kb of memory used
local gui = yawl.widget
local term = require("term")
local os = require("os")
local computer = require("computer")
local root = gui.Frame()             --Create a root frame.
local unicode = require("unicode")
local component = require("component")

root:backgroundColor(0x000000) --0x333333)

local bottomText = gui.Text(root, 1, root:height(), " Press CTRL+C to exit.", 0xffffff)
bottomText:width(root:width())
bottomText:backgroundColor(0x333333)


gui.ToggleSwitch(root, 5, 5, 3, 1)
gui.TextLabel(root, 5, 4, "Click the buttons!")
local linesButton = gui.ToggleSwitch(root, 5, 7, 6, 2)
linesButton:speed(1)

local testInput = gui.TextInput(root, (root:width()-25)/2, 2, "text input")
testInput:size(25, 1)
testInput:backgroundColor(0x113355)

local dropdown = gui.DropdownList(root, testInput:x(), testInput:y()+2, 20, 1, 0x333333)
dropdown:animatedDrop(true) 
dropdown:charSet("+-")
dropdown:listHeight(5)
dropdown:list():list{"This is","a (scrollable) random", "list of", "random things!"}
dropdown:list():select(1, true)
dropdown:list():backgroundColor(0x333333)
dropdown:z(5)
dropdown:list():z(5)
for i=1,10 do dropdown:list():insert(string.format("scroll down %s",i)) end

local braille = gui.SliderBar(root, 3, 15, 14, 1, 1, 8, 0, 0xffffff)
braille:value(1)
braille:range(0x2800+1, 0x28ff)
local brailleText = gui.TextLabel(root, braille:x(), braille:y()+2, "", 0xffffff)
brailleText:width(10)
brailleText:text(braille:value(), unicode.char(braille:value()) or 'none')
braille:callback(function(self, _, eventName, uuid, x, y, button, playerName) 
    self:defaultCallback(_, eventName, uuid, x, y, button, playerName)
    brailleText:text(braille:value(), unicode.char(braille:value()) or 'none')
end)
gui.TextLabel(root, braille:x(), braille:y()-1, "Scroll to see braille characters")

while run do
    os.sleep()
    root:draw()
end
root:Destroy(true) --always call that on all Frame without a parent. This is used to unregister the event listeners for screen related events
component.gpu.freeAllBuffers()
term.clear()
print("Closed yawl-e demo program")