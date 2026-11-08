-- Class helper. A class is the shared metatable of its instances and the metatable of its subclasses,
-- so creating an instance allocates no metatable.

local function call(C, ...)
    if rawget(C, "new") then return C:new(...) end
    return setmetatable(C.parent(...), C)
end

---@class Object
---@field parent Object the parent class
local Object = {__call = call}
Object.__index = Object

function Object:new()
    return setmetatable({}, self)
end

---Test if the object is an instance (or subclass) of a class
---@param C Object
---@return boolean
function Object:instanceOf(C)
    local mt = getmetatable(self)
    while mt do
        if mt == C then return true end
        local index = rawget(mt, "__index")
        -- a plain {__index = class} metatable (subclasses made with other class helpers) leads to its class
        if type(index) == "table" and index ~= mt then mt = index else mt = rawget(mt, "parent") end
    end
    return false
end

setmetatable(Object, {__call = call})

---Create a new class
---@generic C:Object
---@param parent? C Class inherited from
---@return unknown
return function(parent)
    parent = parent or Object
    local C = {parent = parent, __call = call}
    C.__index = C
    return setmetatable(C, parent)
end
