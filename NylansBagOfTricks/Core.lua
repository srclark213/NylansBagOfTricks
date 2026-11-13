local ADDON_NAME, ns = ...

-- Nylan's Bag of Tricks: a collection of small quality-of-life modules.
--
-- Each module registers itself with ns.RegisterModule. Optional fields:
--   savedVariable = "XDB"    global (declared in the TOC) holding the module's flat settings;
--   defaults = { ... }       filled into it and exposed as module.db, even when disabled
--   options = { { key, label, tooltip }, ... }
--                            boolean keys of module.db shown in the settings page
--   module:OnOptionChanged(key, value)
--   module:OnLoad()          our ADDON_LOADED, after saved variables exist (only if enabled)
--   module:OnLogin()         PLAYER_LOGIN (only if enabled)
-- Turning a module on or off takes effect after a UI reload; modules never have to undo
-- their hooks at runtime.

ns.name = ADDON_NAME
ns.title = "Nylan's Bag of Tricks"
ns.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

ns.Modules = {}     -- [key] = module
ns.moduleOrder = {} -- keys, in registration (= TOC) order

function ns.Print(msg)
	print("|cffffd200Bag of Tricks:|r " .. tostring(msg))
end

function ns.RegisterModule(key, info)
	assert(not ns.Modules[key], "Module registered twice: " .. key)
	local module = info or {}
	module.key = key
	module.name = module.name or key
	if module.defaultEnabled == nil then
		module.defaultEnabled = true
	end
	ns.Modules[key] = module
	table.insert(ns.moduleOrder, key)
	return module
end

-- Whether the module is switched on in the settings (may differ from what's running until a reload).
function ns.IsModuleEnabled(key)
	local db = NylansBagOfTricksDB
	return db and db.modules[key] == true
end

-- Whether the module was enabled when the UI loaded, i.e. is actually running.
function ns.IsModuleRunning(key)
	local module = ns.Modules[key]
	return module and module.running == true
end

function ns.SetModuleEnabled(key, enabled)
	NylansBagOfTricksDB.modules[key] = enabled and true or false
	ns.UpdateReloadPrompt()
end

-- True if any module's setting differs from what is running.
function ns.NeedsReload()
	for _, key in ipairs(ns.moduleOrder) do
		if ns.IsModuleEnabled(key) ~= ns.IsModuleRunning(key) then
			return true
		end
	end
	return false
end

StaticPopupDialogs["NYLANS_BAG_OF_TRICKS_RELOAD"] = {
	text = "Nylan's Bag of Tricks:\n\nReload the UI now to apply module changes?",
	button1 = RELOADUI or "Reload UI",
	button2 = LATER or "Later",
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Offer a reload once the settings window closes, so toggling several modules gives one prompt.
function ns.UpdateReloadPrompt()
	ns.reloadPending = ns.NeedsReload()
	if not ns.reloadPending then
		StaticPopup_Hide("NYLANS_BAG_OF_TRICKS_RELOAD")
	end
end

local function CallModules(method)
	for _, key in ipairs(ns.moduleOrder) do
		local module = ns.Modules[key]
		if module.running and module[method] then
			local ok, err = pcall(module[method], module)
			if not ok then
				geterrorhandler()(err)
			end
		end
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		self:UnregisterEvent("ADDON_LOADED")

		NylansBagOfTricksDB = NylansBagOfTricksDB or {}
		local db = NylansBagOfTricksDB
		db.modules = db.modules or {}
		for _, key in ipairs(ns.moduleOrder) do
			local module = ns.Modules[key]
			if db.modules[key] == nil then
				db.modules[key] = module.defaultEnabled
			end
			module.running = db.modules[key] == true

			-- Settings are set up even for disabled modules so the options page can show them.
			if module.savedVariable then
				local saved = _G[module.savedVariable] or {}
				_G[module.savedVariable] = saved
				for k, v in pairs(module.defaults or {}) do
					if saved[k] == nil then
						saved[k] = v
					end
				end
				module.db = saved
			end
		end

		CallModules("OnLoad")
		ns.Settings.Register()
	elseif event == "PLAYER_LOGIN" then
		CallModules("OnLogin")

		-- The modules used to be separate addons; running both copies would double up hooks.
		for _, key in ipairs(ns.moduleOrder) do
			if C_AddOns.IsAddOnLoaded(key) then
				ns.Print(("The old standalone %s addon is still enabled. Disable it in the AddOns list; it's now part of Bag of Tricks."):format(key))
			end
		end
	end
end)

SLASH_NYLANSBAGOFTRICKS1 = "/tricks"
SLASH_NYLANSBAGOFTRICKS2 = "/nbot"
SlashCmdList.NYLANSBAGOFTRICKS = function()
	ns.Settings.Open()
end
