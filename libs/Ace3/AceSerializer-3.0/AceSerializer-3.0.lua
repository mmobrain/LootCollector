

local MAJOR,MINOR = "AceSerializer-3.0", 3
local AceSerializer, oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if not AceSerializer then return end

local strbyte, strchar, gsub, gmatch, format = string.byte, string.char, string.gsub, string.gmatch, string.format
local assert, error, pcall = assert, error, pcall
local type, tostring, tonumber = type, tostring, tonumber
local pairs, select, frexp = pairs, select, math.frexp
local tconcat = table.concat

local serNaN = tostring(0/0)
local serInf = tostring(1/0)
local serNegInf = tostring(-1/0)

local function SerializeStringHelper(ch)	
	
	local n = strbyte(ch)
	if n==30 then           
		return "\126\122"
	elseif n<=32 then 			
		return "\126"..strchar(n+64)
	elseif n==94 then		
		return "\126\125"
	elseif n==126 then		
		return "\126\124"
	elseif n==127 then		
		return "\126\123"
	else
		assert(false)	
	end
end

local function SerializeValue(v, res, nres)
	
	local t=type(v)

	if t=="string" then		
		res[nres+1] = "^S"
		res[nres+2] = gsub(v,"[%c \94\126\127]", SerializeStringHelper)
		nres=nres+2

	elseif t=="number" then	
		local str = tostring(v)
		if tonumber(str)==v  or str==serNaN or str==serInf or str==serNegInf then
			
			res[nres+1] = "^N"
			res[nres+2] = str
			nres=nres+2
		else
			local m,e = frexp(v)
			res[nres+1] = "^F"
			res[nres+2] = format("%.0f",m*2^53)	
			res[nres+3] = "^f"
			res[nres+4] = tostring(e-53)	
			nres=nres+4
		end

	elseif t=="table" then	
		nres=nres+1
		res[nres] = "^T"
		for k,v in pairs(v) do
			nres = SerializeValue(k, res, nres)
			nres = SerializeValue(v, res, nres)
		end
		nres=nres+1
		res[nres] = "^t"

	elseif t=="boolean" then	
		nres=nres+1
		if v then
			res[nres] = "^B"	
		else
			res[nres] = "^b"	
		end

	elseif t=="nil" then		
		nres=nres+1
		res[nres] = "^Z"

	else
		error(MAJOR..": Cannot serialize a value of type '"..t.."'")	
	end

	return nres
end

local serializeTbl = { "^1" }	

function AceSerializer:Serialize(...)
	local nres = 1

	for i=1,select("#", ...) do
		local v = select(i, ...)
		nres = SerializeValue(v, serializeTbl, nres)
	end

	serializeTbl[nres+1] = "^^"	

	return tconcat(serializeTbl, "", 1, nres+1)
end

local function DeserializeStringHelper(escape)
	if escape<"~\122" then
		return strchar(strbyte(escape,2,2)-64)
	elseif escape=="~\122" then	
		return "\030"
	elseif escape=="~\123" then
		return "\127"
	elseif escape=="~\124" then
		return "\126"
	elseif escape=="~\125" then
		return "\94"
	end
	error("DeserializeStringHelper got called for '"..escape.."'?!?")  
end

local function DeserializeNumberHelper(number)
	if number == serNaN then
		return 0/0
	elseif number == serNegInf then
		return -1/0
	elseif number == serInf then
		return 1/0
	else
		return tonumber(number)
	end
end

local function DeserializeValue(iter,single,ctl,data)

	if not single then
		ctl,data = iter()
	end

	if not ctl then
		error("Supplied data misses AceSerializer terminator ('^^')")
	end

	if ctl=="^^" then
		
		return
	end

	local res

	if ctl=="^S" then
		res = gsub(data, "~.", DeserializeStringHelper)
	elseif ctl=="^N" then
		res = DeserializeNumberHelper(data)
		if not res then
			error("Invalid serialized number: '"..tostring(data).."'")
		end
	elseif ctl=="^F" then     
		local ctl2,e = iter()
		if ctl2~="^f" then
			error("Invalid serialized floating-point number, expected '^f', not '"..tostring(ctl2).."'")
		end
		local m=tonumber(data)
		e=tonumber(e)
		if not (m and e) then
			error("Invalid serialized floating-point number, expected mantissa and exponent, got '"..tostring(m).."' and '"..tostring(e).."'")
		end
		res = m*(2^e)
	elseif ctl=="^B" then	
		res = true
	elseif ctl=="^b" then   
		res = false
	elseif ctl=="^Z" then	
		res = nil
	elseif ctl=="^T" then
		
		res = {}
		local k,v
		while true do
			ctl,data = iter()
			if ctl=="^t" then break end	
			k = DeserializeValue(iter,true,ctl,data)
			if k==nil then
				error("Invalid AceSerializer table format (no table end marker)")
			end
			ctl,data = iter()
			v = DeserializeValue(iter,true,ctl,data)
			if v==nil then
				error("Invalid AceSerializer table format (no table end marker)")
			end
			res[k]=v
		end
	else
		error("Invalid AceSerializer control code '"..ctl.."'")
	end

	if not single then
		return res,DeserializeValue(iter)
	else
		return res
	end
end

function AceSerializer:Deserialize(str)
	str = gsub(str, "[%c ]", "")	

	local iter = gmatch(str, "(^.)([^^]*)")	
	local ctl,data = iter()
	if not ctl or ctl~="^1" then
		
		return false, "Supplied data is not AceSerializer data (rev 1)"
	end

	return pcall(DeserializeValue, iter)
end

AceSerializer.internals = {	
	SerializeValue = SerializeValue,
	SerializeStringHelper = SerializeStringHelper,
}

local mixins = {
	"Serialize",
	"Deserialize",
}

AceSerializer.embeds = AceSerializer.embeds or {}

function AceSerializer:Embed(target)
	for k, v in pairs(mixins) do
		target[v] = self[v]
	end
	self.embeds[target] = true
	return target
end

for target, v in pairs(AceSerializer.embeds) do
	AceSerializer:Embed(target)
end
