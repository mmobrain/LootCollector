

local LibBase64 = LibStub:NewLibrary("LibBase64-1.0", 1)

if not LibBase64 then
    return
end

local _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local byteToNum = {}
local numToChar = {}
for i = 1, #_chars do
    numToChar[i - 1] = _chars:sub(i, i)
    byteToNum[_chars:byte(i)] = i - 1
end
_chars = nil
local A_byte = ("A"):byte()
local Z_byte = ("Z"):byte()
local a_byte = ("a"):byte()
local z_byte = ("z"):byte()
local zero_byte = ("0"):byte()
local nine_byte = ("9"):byte()
local plus_byte = ("+"):byte()
local slash_byte = ("/"):byte()
local equals_byte = ("="):byte()
local whitespace = {
    [(" "):byte()] = true,
    [("\t"):byte()] = true,
    [("\n"):byte()] = true,
    [("\r"):byte()] = true,
}

local t = {}

function LibBase64.Encode(text, maxLineLength, lineEnding)
    if type(text) ~= "string" then
        error(("Bad argument #1 to `Encode'. Expected %q, got %q"):format("string", type(text)), 2)
    end
    
    if maxLineLength == nil then
        
    elseif type(maxLineLength) ~= "number" then
        error(("Bad argument #2 to `Encode'. Expected %q or %q, got %q"):format("number", "nil", type(maxLineLength)), 2)
    elseif (maxLineLength % 4) ~= 0 then
        error(("Bad argument #2 to `Encode'. Expected a multiple of 4, got %s"):format(maxLineLength), 2)
    elseif maxLineLength <= 0 then
        error(("Bad argument #2 to `Encode'. Expected a number > 0, got %s"):format(maxLineLength), 2)
    end
    
    if lineEnding == nil then
        lineEnding = "\r\n"
    elseif type(lineEnding) ~= "string" then
        error(("Bad argument #3 to `Encode'. Expected %q, got %q"):format("string", type(lineEnding)), 2)
    end
    
    local currentLength = 0
    
	for i = 1, #text, 3 do
		local a, b, c = text:byte(i, i+2)
		local nilNum = 0
		if not b then
			nilNum = 2
			b = 0
			c = 0
		elseif not c then
			nilNum = 1
			c = 0
		end
		local num = a * 2^16 + b * 2^8 + c
		
		local d = num % 2^6
		num = (num - d) / 2^6
		
		local c = num % 2^6
		num = (num - c) / 2^6
		
		local b = num % 2^6
		num = (num - b) / 2^6
		
		local a = num % 2^6
		
		t[#t+1] = numToChar[a]
		
		t[#t+1] = numToChar[b]
		
		t[#t+1] = (nilNum >= 2) and "=" or numToChar[c]
		
		t[#t+1] = (nilNum >= 1) and "=" or numToChar[d]
		
		currentLength = currentLength + 4
		if maxLineLength and (currentLength % maxLineLength) == 0 then
		    t[#t+1] = lineEnding
		end
	end
	
	local s = table.concat(t)
	for i = 1, #t do
		t[i] = nil
	end
	return s
end

local t2 = {}

function LibBase64.Decode(text)
    if type(text) ~= "string" then
        error(("Bad argument #1 to `Decode'. Expected %q, got %q"):format("string", type(text)), 2)
    end
    
    for i = 1, #text do
        local byte = text:byte(i)
        if whitespace[byte] or byte == equals_byte then
            
        else
            local num = byteToNum[byte]
            if not num then
                for i = 1, #t2 do
                    t2[k] = nil
                end
                
                error(("Bad argument #1 to `Decode'. Received an invalid char: %q"):format(text:sub(i, i)), 2)
            end
            t2[#t2+1] = num
        end
    end
    
    for i = 1, #t2, 4 do
        local a, b, c, d = t2[i], t2[i+1], t2[i+2], t2[i+3]
        
		local nilNum = 0
		if not c then
			nilNum = 2
			c = 0
			d = 0
		elseif not d then
			nilNum = 1
			d = 0
		end
		
		local num = a * 2^18 + b * 2^12 + c * 2^6 + d
		
		local c = num % 2^8
		num = (num - c) / 2^8
		
		local b = num % 2^8
		num = (num - b) / 2^8
		
		local a = num % 2^8
		
		t[#t+1] = string.char(a)
		if nilNum < 2 then
			t[#t+1] = string.char(b)
		end
		if nilNum < 1 then
			t[#t+1] = string.char(c)
		end
	end
	
	for i = 1, #t2 do
		t2[i] = nil
	end
	
	local s = table.concat(t)
	
	for i = 1, #t do
		t[i] = nil
	end
	
	return s
end
