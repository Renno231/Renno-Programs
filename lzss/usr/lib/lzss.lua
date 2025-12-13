local M = {}

-- Cache library functions
local sub, find, char, byte, pack, unpack, rep, concat, max, ceil = string.sub, string.find, string.char, string.byte, string.pack, string.unpack, string.rep, table.concat, math.max, math.ceil
-- Constants
local POS_BITS = 12
local LEN_BITS = 16 - POS_BITS 
local POS_SIZE = 1 << POS_BITS -- 4096
local LEN_SIZE = 1 << LEN_BITS -- 16
local LEN_MIN = 3
local LEN_MAX = LEN_SIZE + LEN_MIN - 1 

function M.compress(input)
    local input_len = #input
    local offset = 1
    local output = {}
    
    while offset <= input_len do
        local flags = 0
        local buffer = {}
        local flag_bit = 1
        
        for i = 0, 7 do
            if offset <= input_len then
                local best_len = 0
                local best_pos = nil
                
                if offset + LEN_MIN <= input_len + 1 then
                    local window_start = (offset > POS_SIZE) and (offset - POS_SIZE) or 1
                    -- LADDER SEARCH INITIALIZATION
                    local search_len = LEN_MIN
                    local signature = sub(input, offset, offset + search_len - 1)
                    local search_ptr = window_start
                    
                    while true do
                        local found_at = find(input, signature, search_ptr, true)
                        
                        if not found_at or found_at >= offset then break end

                        local current_len = search_len
                        while current_len < LEN_MAX and (offset + current_len <= input_len) do
                            if byte(input, offset + current_len) == byte(input, found_at + current_len) then
                                current_len = current_len + 1
                            else
                                break
                            end
                        end
                        
                        if current_len > best_len then
                            best_len = current_len
                            best_pos = found_at
                            if best_len == LEN_MAX then break end
                            
                            -- CLIMB THE LADDER
                            if offset + best_len <= input_len then
                                search_len = best_len + 1
                                signature = sub(input, offset, offset + search_len - 1)
                            else
                                break -- Cannot possibly find a longer match
                            end
                        end
                        
                        search_ptr = found_at + 1
                    end
                end

                if best_len >= LEN_MIN then
                    local window_start = (offset > POS_SIZE) and (offset - POS_SIZE) or 1
                    local rel_pos = best_pos - window_start + 1
                    
                    local token = ((rel_pos - 1) << LEN_BITS) | (best_len - LEN_MIN)
                    buffer[#buffer + 1] = pack('>I2', token)
                    offset = offset + best_len
                else
                    flags = flags | flag_bit
                    buffer[#buffer + 1] = sub(input, offset, offset)
                    offset = offset + 1
                end
            else
                break
            end
            flag_bit = flag_bit << 1
        end

        if #buffer > 0 then
            output[#output + 1] = char(flags)
            output[#output + 1] = concat(buffer)
        end
    end

    return concat(output)
end

function M.decompress(input)
    local offset = 1
    local input_len = #input
    local output = {}
    
    local window = ""
    local window_len = 0
    
    while offset <= input_len do
        local flags = byte(input, offset)
        offset = offset + 1

        local flag_bit = 1
        for i = 1, 8 do
            if offset > input_len then break end
            
            local str
            if (flags & flag_bit) ~= 0 then -- Literal
                str = sub(input, offset, offset)
                offset = offset + 1
            else -- Reference
                if offset + 1 <= input_len then
                    local tmp = unpack('>I2', input, offset)
                    offset = offset + 2
                    
                    local pos = (tmp >> LEN_BITS) + 1
                    local len = (tmp & (LEN_SIZE - 1)) + LEN_MIN
                    
                    local virtual_window_start = max(1, window_len - POS_SIZE + 1)
                    local real_pos = virtual_window_start + pos - 1
                    
                    if (real_pos + len - 1) <= window_len then
                        str = sub(window, real_pos, real_pos + len - 1)
                    else
                        local pattern = sub(window, real_pos, window_len)
                        local repeats = ceil(len / #pattern)
                        str = sub(rep(pattern, repeats), 1, len)
                    end
                end
            end
            
            if str then
                output[#output + 1] = str
                window = window .. str
                window_len = window_len + #str
                
                if window_len > (POS_SIZE * 2) then
                    window = sub(window, -POS_SIZE)
                    window_len = POS_SIZE
                end
            end
            flag_bit = flag_bit << 1
        end
    end

    return concat(output)
end

return M