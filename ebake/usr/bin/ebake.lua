-- eeprom "baking"
--ebake ChunkNameHere < /path/to/input/file.lua > /path/to/bios.lua
local arg = {...}
local lzss = require("lzss")
local mini_lzss = [=[
local C,z,D,E=component,function(a)local b,c,d,e,j,i,h,g=1,'',''while b<=#a do
e=c.byte(a,b)b=b+1
for k=0,7 do h=c.sub
g=h(a,b,b)if e>>k&1<1 and b<#a then
i=c.unpack('>I2',a,b)j=1+(i>>4)g=h(d,j,j+(i&15)+2)b=b+1
end
b=b+1
c=c..g
d=h(d..g,-4^6)end
end
return c end
D=C.proxy(C.list"eeprom"()).get()E=D:match"^...(=*)%["D=D:sub(5+#E):gsub("%]"..E.."%].+","")]=]
local dat = io.stdin:read("*a")
local out = lzss.compress(dat)
local data = out:match("%]=*%]")
local eq = string.rep("=", (data and #data or 1)-1)
io.stdout:write("--["..eq.."[",out,"]"..eq.."]")
io.stdout:write(mini_lzss)
io.stdout:write(string.format("assert(load(z(D),%q))()", "="..(arg[1] or "=(lzss string)")))