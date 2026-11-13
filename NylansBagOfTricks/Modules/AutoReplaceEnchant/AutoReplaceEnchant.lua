local _, ns = ...

-- When you cast an enchant from the profession window onto an item that already has one,
-- the client fires REPLACE_TRADESKILL_ENCHANT and Blizzard shows the REPLACE_TRADESKILL_ENCHANT
-- popup, whose Yes button just calls C_Item.ReplaceTradeskillEnchant(). With the toggle on we
-- do that ourselves and hide the popup.
--
-- Deliberately NOT handled:
--   TRADE_REPLACE_ENCHANT - enchanting someone else's item in the trade window; keep the safety check.
--   REPLACE_ENCHANT       - applying an enchant item (oil, armor kit...) from your bags.

local ARE = ns.RegisterModule("AutoReplaceEnchant", {
	name = "Auto Replace Enchant",
	description = "Adds a checkbox to the enchanting window that skips the \"Do you want to replace ...?\" confirmation.",
	savedVariable = "AutoReplaceEnchantDB",
	defaults = {
		enabled = false, -- the checkbox in the enchanting window
		announce = true, -- print what was replaced
	},
	options = {
		{ key = "enabled", label = "Auto-replace existing enchant",
			tooltip = "Same as the checkbox in the enchanting window." },
		{ key = "announce", label = "Chat message on replace",
			tooltip = "Print which enchant was replaced once the enchant finishes." },
	},
})

local POPUP = "REPLACE_TRADESKILL_ENCHANT"

local db
local checkbox

local function Print(msg)
	print("|cff33ff99Auto Replace Enchant:|r " .. msg)
end

-- The chat message waits until the enchant cast actually finishes, so cancelled or
-- failed casts don't announce anything.
local pendingMessage
local castWatcher = CreateFrame("Frame")
castWatcher:SetScript("OnEvent", function(_, event)
	if event == "UNIT_SPELLCAST_SUCCEEDED" and pendingMessage then
		Print(pendingMessage)
	end
	pendingMessage = nil
end)

local function OnPopupShown(which, existing, replacement)
	if which ~= POPUP or not db.enabled then
		return
	end
	StaticPopup_Hide(POPUP)
	-- Clicking Enchant again while the enchant is already casting brings the prompt back
	-- each time. There's nothing to replace then; just dismiss it.
	if UnitCastingInfo("player") then
		return
	end
	C_Item.ReplaceTradeskillEnchant()
	if db.announce and existing and replacement then
		pendingMessage = ("Replaced %s with %s."):format(existing, replacement)
	end
end

local function IsEnchantRecipeShown(page)
	local form = page.SchematicForm
	local transaction = form and form.GetTransaction and form:GetTransaction()
	return transaction and transaction:IsRecipeType(Enum.TradeskillRecipeType.Enchant)
end

local function UpdateCheckbox()
	if not checkbox then
		return
	end
	local page = ProfessionsFrame.CraftingPage
	checkbox:SetChecked(db.enabled)
	checkbox:SetShown(page.CreateButton:IsShown() and IsEnchantRecipeShown(page))
end

local function CreateCheckbox()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	if checkbox or not page or not page.CreateAllButton then
		return
	end

	checkbox = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	checkbox:SetSize(24, 24)
	-- Sit just above the Enchant All / Enchant button row.
	checkbox:SetPoint("BOTTOMLEFT", page.CreateAllButton, "TOPLEFT", 8, 8)
	checkbox:SetFrameLevel(page.CreateAllButton:GetFrameLevel() + 1)
	checkbox.Text:SetText("Auto-replace existing enchant")
	checkbox.Text:SetFontObject("GameFontHighlightSmall")

	checkbox:SetScript("OnClick", function(self)
		db.enabled = self:GetChecked() and true or false
	end)
	checkbox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Auto-replace existing enchant")
		GameTooltip:AddLine("Skip the \"Do you want to replace ...?\" confirmation when enchanting an item that already has an enchant.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	checkbox:SetScript("OnLeave", GameTooltip_Hide)

	hooksecurefunc(page, "ValidateControls", UpdateCheckbox)
	page:HookScript("OnShow", UpdateCheckbox)
	UpdateCheckbox()
end

local function RegisterSlashCommands()
	SLASH_AUTOREPLACEENCHANT1 = "/autoreplace"
	SLASH_AUTOREPLACEENCHANT2 = "/are"
	SlashCmdList.AUTOREPLACEENCHANT = function(msg)
		msg = strtrim(msg or ""):lower()
		if msg == "on" then
			db.enabled = true
		elseif msg == "off" then
			db.enabled = false
		elseif msg == "announce" then
			db.announce = not db.announce
			Print("Chat message on replace: " .. (db.announce and "on" or "off"))
			return
		elseif msg ~= "" then
			Print("/autoreplace [on | off | announce]")
			return
		end
		if msg == "" then
			db.enabled = not db.enabled
		end
		UpdateCheckbox()
		Print("Auto-replace is " .. (db.enabled and "|cff00ff00on|r" or "|cffff0000off|r") .. ".")
	end
end

function ARE:OnLoad()
	db = self.db

	hooksecurefunc("StaticPopup_Show", OnPopupShown)
	castWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	castWatcher:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
	castWatcher:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
	RegisterSlashCommands()

	-- The profession UI is load-on-demand; another addon may already have loaded it.
	if C_AddOns.IsAddOnLoaded("Blizzard_Professions") then
		CreateCheckbox()
	else
		local waiter = CreateFrame("Frame")
		waiter:RegisterEvent("ADDON_LOADED")
		waiter:SetScript("OnEvent", function(self, _, name)
			if name == "Blizzard_Professions" then
				self:UnregisterAllEvents()
				CreateCheckbox()
			end
		end)
	end
end

function ARE:OnOptionChanged(key, value)
	UpdateCheckbox()
end
