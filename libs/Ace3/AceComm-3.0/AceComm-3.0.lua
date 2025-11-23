

local CallbackHandler = LibStub("CallbackHandler-1.0")
local CTL = assert(ChatThrottleLib, "AceComm-3.0 requires ChatThrottleLib")

local MAJOR, MINOR = "AceComm-3.0", 12
local AceComm,oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if not AceComm then return end

local type, next, pairs, tostring = type, next, pairs, tostring
local strsub, strfind = string.sub, string.find
local tinsert, tconcat = table.insert, table.concat
local error, assert = error, assert

AceComm.embeds = AceComm.embeds or {}

local MSG_MULTI_FIRST = "\001"
local MSG_MULTI_NEXT  = "\002"
local MSG_MULTI_LAST  = "\003"

AceComm.multipart_origprefixes = AceComm.multipart_origprefixes or {} 
AceComm.multipart_reassemblers = AceComm.multipart_reassemblers or {} 

AceComm.multipart_spool = AceComm.multipart_spool or {}

function AceComm:RegisterComm(prefix, method)
	if method == nil then
		method = "OnCommReceived"
	end

	return AceComm._RegisterComm(self, prefix, method)	
end

local warnedPrefix=false

function AceComm:SendCommMessage(prefix, text, distribution, target, prio, callbackFn, callbackArg)
	prio = prio or "NORMAL"	
	if not( type(prefix)=="string" and
			type(text)=="string" and
			type(distribution)=="string" and
			(target==nil or type(target)=="string" or type(target)=="number") and
			(prio=="BULK" or prio=="NORMAL" or prio=="ALERT")
		) then
		error('Usage: SendCommMessage(addon, "prefix", "text", "distribution"[, "target"[, "prio"[, callbackFn, callbackarg]]])', 2)
	end

	if strfind(prefix, "[\001-\009]") then
		if strfind(prefix, "[\001-\003]") then
			error("SendCommMessage: Characters \\001--\\003 in prefix are reserved for AceComm metadata", 2)
		elseif not warnedPrefix then
			
			geterrorhandler()("SendCommMessage: Heads-up developers: Characters \\004--\\009 in prefix are reserved for AceComm future extension")
			warnedPrefix = true
		end
	end

	local textlen = #text
	local maxtextlen = 254 - #prefix	
	local queueName = prefix..distribution..(target or "")

	local ctlCallback = nil
	if callbackFn then
		ctlCallback = function(sent)
			return callbackFn(callbackArg, sent, textlen)
		end
	end

	if textlen <= maxtextlen then
		
		CTL:SendAddonMessage(prio, prefix, text, distribution, target, queueName, ctlCallback, textlen)
	else
		maxtextlen = maxtextlen - 1	

		
		local chunk = strsub(text, 1, maxtextlen)
		CTL:SendAddonMessage(prio, prefix..MSG_MULTI_FIRST, chunk, distribution, target, queueName, ctlCallback, maxtextlen)

		
		local pos = 1+maxtextlen
		local prefix2 = prefix..MSG_MULTI_NEXT

		while pos+maxtextlen <= textlen do
			chunk = strsub(text, pos, pos+maxtextlen-1)
			CTL:SendAddonMessage(prio, prefix2, chunk, distribution, target, queueName, ctlCallback, pos+maxtextlen-1)
			pos = pos + maxtextlen
		end

		
		chunk = strsub(text, pos)
		CTL:SendAddonMessage(prio, prefix..MSG_MULTI_LAST, chunk, distribution, target, queueName, ctlCallback, textlen)
	end
end

do
	local compost = setmetatable({}, {__mode = "k"})
	local function new()
		local t = next(compost)
		if t then
			compost[t]=nil
			for i=#t,3,-1 do	
				t[i]=nil
			end
			return t
		end

		return {}
	end

	local function lostdatawarning(prefix,sender,where)
		DEFAULT_CHAT_FRAME:AddMessage(MAJOR..": Warning: lost network data regarding '"..tostring(prefix).."' from '"..tostring(sender).."' (in "..where..")")
	end

	function AceComm:OnReceiveMultipartFirst(prefix, message, distribution, sender)
		local key = prefix.."\t"..distribution.."\t"..sender	
		local spool = AceComm.multipart_spool

		

		spool[key] = message  
	end

	function AceComm:OnReceiveMultipartNext(prefix, message, distribution, sender)
		local key = prefix.."\t"..distribution.."\t"..sender	
		local spool = AceComm.multipart_spool
		local olddata = spool[key]

		if not olddata then
			
			return
		end

		if type(olddata)~="table" then
			
			local t = new()
			t[1] = olddata    
			t[2] = message    
			spool[key] = t    
		else
			tinsert(olddata, message)
		end
	end

	function AceComm:OnReceiveMultipartLast(prefix, message, distribution, sender)
		local key = prefix.."\t"..distribution.."\t"..sender	
		local spool = AceComm.multipart_spool
		local olddata = spool[key]

		if not olddata then
			
			return
		end

		spool[key] = nil

		if type(olddata) == "table" then
			
			tinsert(olddata, message)
			AceComm.callbacks:Fire(prefix, tconcat(olddata, ""), distribution, sender)
			compost[olddata] = true
		else
			
			AceComm.callbacks:Fire(prefix, olddata..message, distribution, sender)
		end
	end
end

if not AceComm.callbacks then
	
	
	AceComm.__prefixes = {}

	AceComm.callbacks = CallbackHandler:New(AceComm,
						"_RegisterComm",
						"UnregisterComm",
						"UnregisterAllComm")
end

function AceComm.callbacks:OnUsed(target, prefix)
	AceComm.multipart_origprefixes[prefix..MSG_MULTI_FIRST] = prefix
	AceComm.multipart_reassemblers[prefix..MSG_MULTI_FIRST] = "OnReceiveMultipartFirst"

	AceComm.multipart_origprefixes[prefix..MSG_MULTI_NEXT] = prefix
	AceComm.multipart_reassemblers[prefix..MSG_MULTI_NEXT] = "OnReceiveMultipartNext"

	AceComm.multipart_origprefixes[prefix..MSG_MULTI_LAST] = prefix
	AceComm.multipart_reassemblers[prefix..MSG_MULTI_LAST] = "OnReceiveMultipartLast"
end

function AceComm.callbacks:OnUnused(target, prefix)
	AceComm.multipart_origprefixes[prefix..MSG_MULTI_FIRST] = nil
	AceComm.multipart_reassemblers[prefix..MSG_MULTI_FIRST] = nil

	AceComm.multipart_origprefixes[prefix..MSG_MULTI_NEXT] = nil
	AceComm.multipart_reassemblers[prefix..MSG_MULTI_NEXT] = nil

	AceComm.multipart_origprefixes[prefix..MSG_MULTI_LAST] = nil
	AceComm.multipart_reassemblers[prefix..MSG_MULTI_LAST] = nil
end

local function OnEvent(this, event, ...)
	if event == "CHAT_MSG_ADDON" then
		local prefix,message,distribution,sender = ...
		local reassemblername = AceComm.multipart_reassemblers[prefix]
		if reassemblername then
			
			local aceCommReassemblerFunc = AceComm[reassemblername]
			local origprefix = AceComm.multipart_origprefixes[prefix]
			aceCommReassemblerFunc(AceComm, origprefix, message, distribution, sender)
		else
			
			AceComm.callbacks:Fire(prefix, message, distribution, sender)
		end
	else
		assert(false, "Received "..tostring(event).." event?!")
	end
end

AceComm.frame = AceComm.frame or CreateFrame("Frame", "AceComm30Frame")
AceComm.frame:SetScript("OnEvent", OnEvent)
AceComm.frame:UnregisterAllEvents()
AceComm.frame:RegisterEvent("CHAT_MSG_ADDON")

local mixins = {
	"RegisterComm",
	"UnregisterComm",
	"UnregisterAllComm",
	"SendCommMessage",
}

function AceComm:Embed(target)
	for k, v in pairs(mixins) do
		target[v] = self[v]
	end
	self.embeds[target] = true
	return target
end

function AceComm:OnEmbedDisable(target)
	target:UnregisterAllComm()
end

for target, v in pairs(AceComm.embeds) do
	AceComm:Embed(target)
end
