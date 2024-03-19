--[[
    basically, Window is the ported (and upgraded) version of the Window that I create for my legacy GDS visual library.
    would need to use border draw override and draw border manually
    is ScrollFrame, has only one _childs index, but multiple _childs tables stored within each "tab"
    e.g.,
    
        self._tabs = { ['tabname'] = {_childs = {}, displayName = string, tabX = num, tabY = num, scrollX = num, scrollY = num } }
        self._selectedTab = self._tabs[tabname] --used in :draw()
        end
    each "tab" needs to be a Tab object which contains the following
        {_childs = {}, parent = somewindow, displayName = string, tabX = num, tabY = num, scrollX = num, scrollY = num, addChild = function(child) self._parent.addChild(self, child) child:setParent(self._parent, false) end, removeChild = ScrollFrame.removeChild }
    needs to override clearChildren
]]

local keyboard = require('keyboard')
local class = require("libClass2")
local ScrollFrame = require("yawl-e.widget.ScrollFrame")
local Tab = require("yawl-e.util").Tab
local unicode = require("unicode")
local computer = require("computer")
local gpu = require("component").gpu

local Window = class(ScrollFrame) 

function Window:new(parentFrame, x, y, width, height)
    checkArg(1, parentFrame, 'table', 'nil')
    checkArg(2, x, 'number', 'nil')
    checkArg(3, y, 'number', 'nil')
    checkArg(4, width, 'number', 'nil')
    checkArg(5, height, 'number', 'nil')
    local o = self.parent(parentFrame, x, y)
    setmetatable(o, {__index = self})
    o._tabs = {} --might need an unordered version
    o._tabsSorted = {}
    o._tabCount = 0
    o._borderoverride = true
    o._hitboxTop = {} --each index represents x coordinate where a tab is drawn and points towards the tab drawn
    o._hitboxBottom = {}
    o:size(width, height)
    o:propagateFirst(true)
    --self._selectedTab
    return o
end

function Window:propagateEvent(eName, screenAddress, x, y, ...)
    local isBordered = self:bordered()
    local abx, aby = self:absX() + (isBordered and 1 or 0), self:absY() + (isBordered and 1 or 0)
    local width, height = self:width() + (isBordered and -2 or 0), self:height() + (isBordered and -2 or 0)
    -- checking if the event is on the edge of the window
    if (x < abx ) then return false end
    if (x > abx + width - 1) then return false end
    if (y < aby) then return false end
    if (y > aby + height - 1) then return false end
    local hitbox = (y == aby and self._hitboxBottom) or (y == aby+height-1 and self._hitboxTop)
    local tab = hitbox and hitbox[x]
    if tab then --need to account for border?
        return false
    end
    return ScrollFrame.propagateEvent(self, eName, screenAddress, x, y, ...)
end

--need to decide how to add widgets to different tabs
function Window:tab(tabName) --retrieves tab if it exists
    checkArg(1, tabName, 'string', 'nil')
    return tabName and self._tabs[tabName] or self._selectedTab --or self ?
end

function Window:clearChildren()
    local foundTab = self._selectedTab
    if foundTab and foundTab._childs and #foundTab._childs>0 then
        for _, widget in ipairs (foundTab._childs) do
            widget:Destroy(true)
        end
        foundTab._childs = {}
        self._childs = foundTab._childs
    end
    
    return true
end

function Window:openTab(name, x, y) --perhaps should tabs now be allowed to overlap? such that x represents the index in the tab list and y reprents top or bottom? could also 
    --make new tab
    checkArg(1, name, "string")
    checkArg(2, x, "number", 'nil')
    checkArg(3, y, "number", 'nil')
    local foundTab = self:tab(name)
    if foundTab then
        self:closeTab(name)
    end
    local newtab = Tab:new(self, name, x or 0, y or 0)
    self._tabs[name] = newtab
    table.insert(self._tabsSorted, newtab)

    self:invokeCallback("openedTab", #self._tabsSorted, newtab)
    self._tabCount = self._tabCount + 1
end

function Window:closeTab(name)
    checkArg(1, name, 'string')
    local foundTab = self:tab(name)
    if foundTab then
        self._tabCount = self._tabCount - 1
        if foundTab == self._selectedTab then --should select the next one in _sortedTabs if there is one
            if self._tabCount == 0 then 
                self._childs = {}
            else
                local sortedIndex
                for i, tab in ipairs (self._tabsSorted) do
                    if tab == foundTab then sortedIndex = i break end
                end
                self:selectTab(sortedIndex ~= #self._tabsSorted and sortedIndex + 1 or sortedIndex - 1)
            end
        end
        for _, widget in ipairs (foundTab._childs) do
            widget:Destroy(true)
        end
        for key, _ in pairs (foundTab) do
            rawset(foundTab, key, nil)
        end
        self._tabs[name] = nil
        local foundi
        for i, tab in ipairs (self._tabsSorted) do
            if tab == foundTab then foundi = i break end
        end
            
        self:invokeCallback("closedTab", foundi, self._tabsSorted[foundi])
        table.remove(self._tabsSorted, foundi)
    end
end

function Window:renameTab(name, newname)

end

function Window:selectTab(tabname, state) --method name not set in stone
    checkArg(1, tabname, 'string', 'number')
    local foundTab = type(tabname) == "string" and self:tab(tabname) or self._tabsSorted[tabname]
    if foundTab then
        self._selectedTab = foundTab
        self._childs = foundTab._childs
        self:scrollX(foundTab._scrollX, true)
        self:scrollY(foundTab._scrollY, true)
        foundTab._lastSelected = computer.uptime()
        self:invokeCallback("selectedTab", foundTab)
    end
end

function Window:_sortTabs()
    table.sort(self._tabsSorted, function(a,b) return a._lastSelected > b._lastSelected end)
end

function Window:defaultCallback(_, eventName, uuid, x, y, button, playerName) --needs refinement
    --require("component").ocelot.log(string.format("%s %s", eventName, require("computer").uptime()))
    local tab = self:tab()
    if eventName == "touch" then
        local abx, aby, width, height = self:absX(), self:absY(), self:width(), self:height()
        local hitbox = (y == aby and self._hitboxBottom) or (y == aby+height-1 and self._hitboxTop)
        if not hitbox then return end
        local tab = hitbox and hitbox[x] 
        --[[local str = ""
        for i,v in pairs (hitbox) do str = str == "" and i or str .. " " .. i end
        require("component").ocelot.log(string.format("%s %s %s %s (%s)", hitbox, tab, x,y, str))]]
        if tab then --need to account for border?
            self:selectTab(tab._name)
        elseif not self:bordered() and hitbox then 
            return
        end
        return true
    elseif eventName=="scroll" and tab then 
        local currentScrollX, currentScrollY = tab:scrollX(), tab:scrollY()
        if keyboard.isControlDown() then
            local minX, maxX = self:minimumScrollX(), self:maximumScrollX()
            if (button == -1 and currentScrollX-button >= (minX or 2)) or (button == 1 and currentScrollX-button <= (maxX or -2)) then
                tab:scrollX(button)
                self:scrollX(tab:scrollX(), true)
                return true
            end
        else
            local minY, maxY = self:minimumScrollY(), self:maximumScrollY()
            if (button == 1 and currentScrollY-button >= (minY or 0)) or (button == -1 and currentScrollY-button <= (maxY or 0)) then
                tab:scrollY(-button) -- this is firing twice ONLY on the Main window in client.lua
                -- local now = require"computer".uptime()
                -- if self._debug then self._debug:text(now, (self._lastfuck or 0) == now) end
                -- self._lastfuck = now
                self:scrollY(tab:scrollY(), true)
                return true
            end
        end
    end
end

function Window:tabChars(chars)
    checkArg(1, chars, 'string', 'nil', 'boolean')
    local oldValue = self._tabJacket 
    if type(chars) == 'string' then
        self._tabJacket = unicode.sub(chars, 1, 2)
    elseif chars == false then
        self._tabJacket = false 
    end
    return oldValue
end

function Window:draw() --should widgets in non selected tabs still get tween and weld updates?
    --frame default draw, then border draw on self, then draw the tabs on self over the border
    ScrollFrame.draw(self)
    if not self:visible() then return end
    self:drawBorder()
    self._hitboxTop = {} --each index represents x coordinate where a tab is drawn and points towards the tab drawn
    self._hitboxBottom = {}
    if self._tabCount == 0 then return end
    self:_sortTabs()
    local width, height = self:size()
    local x, y = self:absX(), self:absY()
    local isBordered = self:bordered()
    local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()
    local newBG, newFG = self:backgroundColor(), self:foregroundColor()
    if newBG then gpu.setBackground(newBG) end
    if newFG then gpu.setForeground(newFG) end
    for i = #self._tabsSorted, 1, -1 do
        local tab = self._tabsSorted[i]
        local tabDisplayName = tab:displayName()
        if type(tabDisplayName) == "function" then 
            local succ, returned = pcall(tabDisplayName) --maybe just set tabDisplayName to returned directly?
            tabDisplayName = not succ and 'Callback Error' or tostring(returned) 
        end
        local tabJacket = self:tabChars() --maybe delegate to each tab
        --[[if tabJacket then
            tabDisplayName = unicode.charAt(tabJacket, 1) .. tabDisplayName .. unicode.charAt(tabJacket, 2)
        end]]
        local tabX, tabY, nameLen = tab._tabX, tab._tabY, unicode.len(tabDisplayName)
        if isBordered and tabX == 0 then
            tabX = 1
        end
        if nameLen > 0 then
            local relativeY = tabY > 1 and y+height-1 or y
            local hitbox = tabY > 1 and self._hitboxTop or self._hitboxBottom
            local overlap = tabX + nameLen - width
            if tabJacket then
                if tabX >= 0 and overlap < 0 then
                    self:_gpuset(x+tabX, relativeY, unicode.charAt(tabJacket, 1))
                    hitbox[x + tabX] = nil
                    self:_gpuset(x+tabX+nameLen+1, relativeY, unicode.charAt(tabJacket, 2))
                    hitbox[x + tabX + nameLen+1] = nil
                    tabX = tabX + 1
                end
            end
            if overlap > 0 then
                tabDisplayName = unicode.sub(tabDisplayName, 1, nameLen - overlap - 1)
            end
            if tabX < 0 then
                tabDisplayName = unicode.sub(tabDisplayName, math.abs(tabX)+1, nameLen)
                tabX = 0
            end
            local isSelected = self._selectedTab and tab == self._selectedTab
            if isSelected then gpu.setBackground(oldFG) gpu.setForeground(oldBG) end
            self:_gpuset(x+tabX, relativeY, tabDisplayName, true)
            for i = 1, nameLen do
                hitbox[x + tabX + i - 1] = tab
            end
            if isSelected then gpu.setBackground(oldBG) gpu.setForeground(oldFG) end
            --do edge check with window width, if bordered then it has to be width -1, if tabX == 0 and bordered, tabX = 1
            -- need to do check if this tab is the selected tab and invert colors if they exist,
        end
    end
end

function Window:Destroy(force)
    if force then
        for tabname, _ in pairs (self._tabs) do
            self:closeTab(tabname)    
        end
    end
    ScrollFrame.Destroy(self, force)
end

return Window