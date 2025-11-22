

local MAJOR, MINOR = "AceAddon-3.0", 12
local AceAddon, oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if not AceAddon then return end 

AceAddon.frame = AceAddon.frame or CreateFrame("Frame", "AceAddon30Frame") 
AceAddon.addons = AceAddon.addons or {} 
AceAddon.statuses = AceAddon.statuses or {} 
AceAddon.initializequeue = AceAddon.initializequeue or {} 
AceAddon.enablequeue = AceAddon.enablequeue or {} 
AceAddon.embeds = AceAddon.embeds or setmetatable({}, {__index = function(tbl, key) tbl[key] = {} return tbl[key] end }) 

local tinsert, tconcat, tremove = table.insert, table.concat, table.remove
local fmt, tostring = string.format, tostring
local select, pairs, next, type, unpack = select, pairs, next, type, unpack
local loadstring, assert, error = loadstring, assert, error
local setmetatable, getmetatable, rawset, rawget = setmetatable, getmetatable, rawset, rawget

local xpcall = xpcall

local function errorhandler(err)
	return geterrorhandler()(err)
end

local function CreateDispatcher(argCount)
	local code = [[
		local xpcall, eh = ...
		local method, ARGS
		local function call() return method(ARGS) end

		local function dispatch(func, ...)
			 method = func
			 if not method then return end
			 ARGS = ...
			 return xpcall(call, eh)
		end

		return dispatch
	]]

	local ARGS = {}
	for i = 1, argCount do ARGS[i] = "arg"..i end
	code = code:gsub("ARGS", tconcat(ARGS, ", "))
	return assert(loadstring(code, "safecall Dispatcher["..argCount.."]"))(xpcall, errorhandler)
end

local Dispatchers = setmetatable({}, {__index=function(self, argCount)
	local dispatcher = CreateDispatcher(argCount)
	rawset(self, argCount, dispatcher)
	return dispatcher
end})
Dispatchers[0] = function(func)
	return xpcall(func, errorhandler)
end

local function safecall(func, ...)
	
	
	
	if type(func) == "function" then
		return Dispatchers[select('#', ...)](func, ...)
	end
end

local Enable, Disable, EnableModule, DisableModule, Embed, NewModule, GetModule, GetName, SetDefaultModuleState, SetDefaultModuleLibraries, SetEnabledState, SetDefaultModulePrototype

local function addontostring( self ) return self.name end

local function queuedForInitialization(addon)
	for i = 1, #AceAddon.initializequeue do
		if AceAddon.initializequeue[i] == addon then
			return true
		end
	end
	return false
end

function AceAddon:NewAddon(objectorname, ...)
	local object,name
	local i=1
	if type(objectorname)=="table" then
		object=objectorname
		name=...
		i=2
	else
		name=objectorname
	end
	if type(name)~="string" then
		error(("Usage: NewAddon([object,] name, [lib, lib, lib, ...]): 'name' - string expected got '%s'."):format(type(name)), 2)
	end
	if self.addons[name] then
		error(("Usage: NewAddon([object,] name, [lib, lib, lib, ...]): 'name' - Addon '%s' already exists."):format(name), 2)
	end

	object = object or {}
	object.name = name

	local addonmeta = {}
	local oldmeta = getmetatable(object)
	if oldmeta then
		for k, v in pairs(oldmeta) do addonmeta[k] = v end
	end
	addonmeta.__tostring = addontostring

	setmetatable( object, addonmeta )
	self.addons[name] = object
	object.modules = {}
	object.orderedModules = {}
	object.defaultModuleLibraries = {}
	Embed( object ) 
	self:EmbedLibraries(object, select(i,...))

	
	tinsert(self.initializequeue, object)
	return object
end

function AceAddon:GetAddon(name, silent)
	if not silent and not self.addons[name] then
		error(("Usage: GetAddon(name): 'name' - Cannot find an AceAddon '%s'."):format(tostring(name)), 2)
	end
	return self.addons[name]
end

function AceAddon:EmbedLibraries(addon, ...)
	for i=1,select("#", ... ) do
		local libname = select(i, ...)
		self:EmbedLibrary(addon, libname, false, 4)
	end
end

function AceAddon:EmbedLibrary(addon, libname, silent, offset)
	local lib = LibStub:GetLibrary(libname, true)
	if not lib and not silent then
		error(("Usage: EmbedLibrary(addon, libname, silent, offset): 'libname' - Cannot find a library instance of %q."):format(tostring(libname)), offset or 2)
	elseif lib and type(lib.Embed) == "function" then
		lib:Embed(addon)
		tinsert(self.embeds[addon], libname)
		return true
	elseif lib then
		error(("Usage: EmbedLibrary(addon, libname, silent, offset): 'libname' - Library '%s' is not Embed capable"):format(libname), offset or 2)
	end
end

function GetModule(self, name, silent)
	if not self.modules[name] and not silent then
		error(("Usage: GetModule(name, silent): 'name' - Cannot find module '%s'."):format(tostring(name)), 2)
	end
	return self.modules[name]
end

local function IsModuleTrue(self) return true end

function NewModule(self, name, prototype, ...)
	if type(name) ~= "string" then error(("Usage: NewModule(name, [prototype, [lib, lib, lib, ...]): 'name' - string expected got '%s'."):format(type(name)), 2) end
	if type(prototype) ~= "string" and type(prototype) ~= "table" and type(prototype) ~= "nil" then error(("Usage: NewModule(name, [prototype, [lib, lib, lib, ...]): 'prototype' - table (prototype), string (lib) or nil expected got '%s'."):format(type(prototype)), 2) end

	if self.modules[name] then error(("Usage: NewModule(name, [prototype, [lib, lib, lib, ...]): 'name' - Module '%s' already exists."):format(name), 2) end

	
	
	local module = AceAddon:NewAddon(fmt("%s_%s", self.name or tostring(self), name))

	module.IsModule = IsModuleTrue
	module:SetEnabledState(self.defaultModuleState)
	module.moduleName = name

	if type(prototype) == "string" then
		AceAddon:EmbedLibraries(module, prototype, ...)
	else
		AceAddon:EmbedLibraries(module, ...)
	end
	AceAddon:EmbedLibraries(module, unpack(self.defaultModuleLibraries))

	if not prototype or type(prototype) == "string" then
		prototype = self.defaultModulePrototype or nil
	end

	if type(prototype) == "table" then
		local mt = getmetatable(module)
		mt.__index = prototype
		setmetatable(module, mt)  
	end

	safecall(self.OnModuleCreated, self, module) 
	self.modules[name] = module
	tinsert(self.orderedModules, module)

	return module
end

function GetName(self)
	return self.moduleName or self.name
end

function Enable(self)
	self:SetEnabledState(true)

	
	
	if not queuedForInitialization(self) then
		return AceAddon:EnableAddon(self)
	end
end

function Disable(self)
	self:SetEnabledState(false)
	return AceAddon:DisableAddon(self)
end

function EnableModule(self, name)
	local module = self:GetModule( name )
	return module:Enable()
end

function DisableModule(self, name)
	local module = self:GetModule( name )
	return module:Disable()
end

function SetDefaultModuleLibraries(self, ...)
	if next(self.modules) then
		error("Usage: SetDefaultModuleLibraries(...): cannot change the module defaults after a module has been registered.", 2)
	end
	self.defaultModuleLibraries = {...}
end

function SetDefaultModuleState(self, state)
	if next(self.modules) then
		error("Usage: SetDefaultModuleState(state): cannot change the module defaults after a module has been registered.", 2)
	end
	self.defaultModuleState = state
end

function SetDefaultModulePrototype(self, prototype)
	if next(self.modules) then
		error("Usage: SetDefaultModulePrototype(prototype): cannot change the module defaults after a module has been registered.", 2)
	end
	if type(prototype) ~= "table" then
		error(("Usage: SetDefaultModulePrototype(prototype): 'prototype' - table expected got '%s'."):format(type(prototype)), 2)
	end
	self.defaultModulePrototype = prototype
end

function SetEnabledState(self, state)
	self.enabledState = state
end

local function IterateModules(self) return pairs(self.modules) end

local function IterateEmbeds(self) return pairs(AceAddon.embeds[self]) end

local function IsEnabled(self) return self.enabledState end
local mixins = {
	NewModule = NewModule,
	GetModule = GetModule,
	Enable = Enable,
	Disable = Disable,
	EnableModule = EnableModule,
	DisableModule = DisableModule,
	IsEnabled = IsEnabled,
	SetDefaultModuleLibraries = SetDefaultModuleLibraries,
	SetDefaultModuleState = SetDefaultModuleState,
	SetDefaultModulePrototype = SetDefaultModulePrototype,
	SetEnabledState = SetEnabledState,
	IterateModules = IterateModules,
	IterateEmbeds = IterateEmbeds,
	GetName = GetName,
}
local function IsModule(self) return false end
local pmixins = {
	defaultModuleState = true,
	enabledState = true,
	IsModule = IsModule,
}

function Embed(target, skipPMixins)
	for k, v in pairs(mixins) do
		target[k] = v
	end
	if not skipPMixins then
		for k, v in pairs(pmixins) do
			target[k] = target[k] or v
		end
	end
end

function AceAddon:InitializeAddon(addon)
	safecall(addon.OnInitialize, addon)

	local embeds = self.embeds[addon]
	for i = 1, #embeds do
		local lib = LibStub:GetLibrary(embeds[i], true)
		if lib then safecall(lib.OnEmbedInitialize, lib, addon) end
	end

	
	
end

function AceAddon:EnableAddon(addon)
	if type(addon) == "string" then addon = AceAddon:GetAddon(addon) end
	if self.statuses[addon.name] or not addon.enabledState then return false end

	
	self.statuses[addon.name] = true

	safecall(addon.OnEnable, addon)

	
	if self.statuses[addon.name] then
		local embeds = self.embeds[addon]
		for i = 1, #embeds do
			local lib = LibStub:GetLibrary(embeds[i], true)
			if lib then safecall(lib.OnEmbedEnable, lib, addon) end
		end

		
		local modules = addon.orderedModules
		for i = 1, #modules do
			self:EnableAddon(modules[i])
		end
	end
	return self.statuses[addon.name] 
end

function AceAddon:DisableAddon(addon)
	if type(addon) == "string" then addon = AceAddon:GetAddon(addon) end
	if not self.statuses[addon.name] then return false end

	
	self.statuses[addon.name] = false

	safecall( addon.OnDisable, addon )

	
	if not self.statuses[addon.name] then
		local embeds = self.embeds[addon]
		for i = 1, #embeds do
			local lib = LibStub:GetLibrary(embeds[i], true)
			if lib then safecall(lib.OnEmbedDisable, lib, addon) end
		end
		
		local modules = addon.orderedModules
		for i = 1, #modules do
			self:DisableAddon(modules[i])
		end
	end

	return not self.statuses[addon.name] 
end

function AceAddon:IterateAddons() return pairs(self.addons) end

function AceAddon:IterateAddonStatus() return pairs(self.statuses) end

function AceAddon:IterateEmbedsOnAddon(addon) return pairs(self.embeds[addon]) end
function AceAddon:IterateModulesOfAddon(addon) return pairs(addon.modules) end

local function onEvent(this, event, arg1)
	
	if (event == "ADDON_LOADED"  and arg1 ~= "Blizzard_DebugTools") or event == "PLAYER_LOGIN" then
		
		while(#AceAddon.initializequeue > 0) do
			local addon = tremove(AceAddon.initializequeue, 1)
			
			if event == "ADDON_LOADED" then addon.baseName = arg1 end
			AceAddon:InitializeAddon(addon)
			tinsert(AceAddon.enablequeue, addon)
		end

		if IsLoggedIn() then
			while(#AceAddon.enablequeue > 0) do
				local addon = tremove(AceAddon.enablequeue, 1)
				AceAddon:EnableAddon(addon)
			end
		end
	end
end

AceAddon.frame:RegisterEvent("ADDON_LOADED")
AceAddon.frame:RegisterEvent("PLAYER_LOGIN")
AceAddon.frame:SetScript("OnEvent", onEvent)

for name, addon in pairs(AceAddon.addons) do
	Embed(addon, true)
end

if oldminor and oldminor < 10 then
	for name, addon in pairs(AceAddon.addons) do
		addon.orderedModules = {}
		for module_name, module in pairs(addon.modules) do
			tinsert(addon.orderedModules, module)
		end
	end
end
