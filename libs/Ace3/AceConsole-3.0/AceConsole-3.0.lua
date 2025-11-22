

local MAJOR,MINOR = "AceConsole-3.0", 7

local AceConsole, oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if not AceConsole then return end 

AceConsole.embeds = AceConsole.embeds or {} 
AceConsole.commands = AceConsole.commands or {} 
AceConsole.weakcommands = AceConsole.weakcommands or {} 

local tconcat, tostring, select = table.concat, tostring, select
local type, pairs, error = type, pairs, error
local format, strfind, strsub = string.format, string.find, string.sub
local max = math.max

local _G = _G

local tmp={}
local function Print(self,frame,...)
	local n=0
	if self ~= AceConsole then
		n=n+1
		tmp[n] = "|cff33ff99"..tostring( self ).."|r:"
	end
	for i=1, select("#", ...) do
		n=n+1
		tmp[n] = tostring(select(i, ...))
	end
	frame:AddMessage( tconcat(tmp," ",1,n) )
end

function AceConsole:Print(...)
	local frame = ...
	if type(frame) == "table" and frame.AddMessage then	
		return Print(self, frame, select(2,...))
	else
		return Print(self, DEFAULT_CHAT_FRAME, ...)
	end
end

function AceConsole:Printf(...)
	local frame = ...
	if type(frame) == "table" and frame.AddMessage then	
		return Print(self, frame, format(select(2,...)))
	else
		return Print(self, DEFAULT_CHAT_FRAME, format(...))
	end
end

function AceConsole:RegisterChatCommand( command, func, persist )
	if type(command)~="string" then error([[Usage: AceConsole:RegisterChatCommand( "command", func[, persist ]): 'command' - expected a string]], 2) end

	if persist==nil then persist=true end	

	local name = "ACECONSOLE_"..command:upper()

	if type( func ) == "string" then
		SlashCmdList[name] = function(input, editBox)
			self[func](self, input, editBox)
		end
	else
		SlashCmdList[name] = func
	end
	_G["SLASH_"..name.."1"] = "/"..command:lower()
	AceConsole.commands[command] = name
	
	if not persist then
		if not AceConsole.weakcommands[self] then AceConsole.weakcommands[self] = {} end
		AceConsole.weakcommands[self][command] = func
	end
	return true
end

function AceConsole:UnregisterChatCommand( command )
	local name = AceConsole.commands[command]
	if name then
		SlashCmdList[name] = nil
		_G["SLASH_" .. name .. "1"] = nil
		hash_SlashCmdList["/" .. command:upper()] = nil
		AceConsole.commands[command] = nil
	end
end

function AceConsole:IterateChatCommands() return pairs(AceConsole.commands) end

local function nils(n, ...)
	if n>1 then
		return nil, nils(n-1, ...)
	elseif n==1 then
		return nil, ...
	else
		return ...
	end
end

function AceConsole:GetArgs(str, numargs, startpos)
	numargs = numargs or 1
	startpos = max(startpos or 1, 1)

	local pos=startpos

	
	pos = strfind(str, "[^ ]", pos)
	if not pos then	
		return nils(numargs, 1e9)
	end

	if numargs<1 then
		return pos
	end

	
	local delim_or_pipe
	local ch = strsub(str, pos, pos)
	if ch=='"' then
		pos = pos + 1
		delim_or_pipe='([|"])'
	elseif ch=="'" then
		pos = pos + 1
		delim_or_pipe="([|'])"
	else
		delim_or_pipe="([| ])"
	end

	startpos = pos

	while true do
		
		local ch,_
		pos,_,ch = strfind(str, delim_or_pipe, pos)

		if not pos then break end

		if ch=="|" then
			

			if strsub(str,pos,pos+1)=="|H" then
				
				pos=strfind(str, "|h", pos+2)	
				if not pos then break end

				pos=strfind(str, "|h", pos+2)	
				if not pos then break end
			elseif strsub(str,pos, pos+1) == "|T" then
				
				pos=strfind(str, "|t", pos+2)
				if not pos then break end
			end

			pos=pos+2 

		else
			
			return strsub(str, startpos, pos-1), AceConsole:GetArgs(str, numargs-1, pos+1)
		end

	end

	
	return strsub(str, startpos), nils(numargs-1, 1e9)
end

local mixins = {
	"Print",
	"Printf",
	"RegisterChatCommand",
	"UnregisterChatCommand",
	"GetArgs",
}

function AceConsole:Embed( target )
	for k, v in pairs( mixins ) do
		target[v] = self[v]
	end
	self.embeds[target] = true
	return target
end

function AceConsole:OnEmbedEnable( target )
	if AceConsole.weakcommands[target] then
		for command, func in pairs( AceConsole.weakcommands[target] ) do
			target:RegisterChatCommand( command, func, false, true ) 
		end
	end
end

function AceConsole:OnEmbedDisable( target )
	if AceConsole.weakcommands[target] then
		for command, func in pairs( AceConsole.weakcommands[target] ) do
			target:UnregisterChatCommand( command ) 
		end
	end
end

for addon in pairs(AceConsole.embeds) do
	AceConsole:Embed(addon)
end
