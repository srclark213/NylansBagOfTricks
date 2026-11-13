local _, ns = ...

-- One settings page under Options > AddOns > Nylan's Bag of Tricks: a plain list where each
-- module is a checkbox labelled with its name, with its own options nested under it
-- (greyed out while the module is switched off). If this gets crowded, modules can move to
-- subcategories via Settings.RegisterVerticalLayoutSubcategory.

local Settings_ = {}
ns.Settings = Settings_

local category

local function AddModuleSection(layout, module)
	local key = module.key

	local enableSetting = Settings.RegisterProxySetting(category, "NYLANS_BAG_OF_TRICKS_MODULE_" .. key,
		Settings.VarType.Boolean, module.name, module.defaultEnabled,
		function() return ns.IsModuleEnabled(key) end,
		function(value) ns.SetModuleEnabled(key, value) end)
	local enableInit = Settings.CreateCheckbox(category, enableSetting,
		(module.description or "") .. "\n\nApplies after reloading the UI.")

	local function IsEnabled()
		return ns.IsModuleEnabled(key)
	end

	for _, option in ipairs(module.options or {}) do
		local optionKey = option.key
		local setting = Settings.RegisterProxySetting(category,
			"NYLANS_BAG_OF_TRICKS_" .. key .. "_" .. optionKey,
			Settings.VarType.Boolean, option.label, module.defaults[optionKey],
			function() return module.db[optionKey] end,
			function(value)
				module.db[optionKey] = value
				if module.running and module.OnOptionChanged then
					module:OnOptionChanged(optionKey, value)
				end
			end)
		local init = Settings.CreateCheckbox(category, setting, option.tooltip)
		init:SetParentInitializer(enableInit, IsEnabled)
	end
end

function Settings_.Register()
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory(ns.title)

	for _, key in ipairs(ns.moduleOrder) do
		AddModuleSection(layout, ns.Modules[key])
	end

	Settings.RegisterAddOnCategory(category)

	-- Ask about reloading when the options window closes with module changes pending.
	if SettingsPanel then
		SettingsPanel:HookScript("OnHide", function()
			if ns.reloadPending and ns.NeedsReload() then
				StaticPopup_Show("NYLANS_BAG_OF_TRICKS_RELOAD")
			end
		end)
	end
end

function Settings_.Open()
	if category then
		Settings.OpenToCategory(category:GetID())
	end
end
