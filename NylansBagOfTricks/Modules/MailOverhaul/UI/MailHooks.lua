local _, ns = ...
local MO = ns.Modules.MailOverhaul

-- Additions to Blizzard's Send Mail tab:
--  * a suggestion list under the "To:" box driven by the address book
--  * an address book button next to the "To:" box
--  * a "MailOverhaul" button to switch to the MailOverhaul mailbox window
local MailHooks = {}
MO.MailHooks = MailHooks

local W = MO.Widgets
local Contacts = MO.Contacts
local Names = MO.Names

local MAX_SUGGESTIONS = 8
local suggestFrame
local selectedIndex = 0
local results = {}
local blizzardSource -- Blizzard's autocomplete source, saved so we can restore it

local function SetBlizzardAutocomplete(enabled)
	local box = SendMailNameEditBox
	if enabled then
		if blizzardSource then
			box.autoCompleteSource = blizzardSource
		end
	else
		blizzardSource = blizzardSource or box.autoCompleteSource
		box.autoCompleteSource = nil -- AutoComplete_Update bails out without a source
		if AutoComplete_HideIfAttachedTo then
			AutoComplete_HideIfAttachedTo(box)
		end
	end
end

function MailHooks.ApplySettings()
	SetBlizzardAutocomplete(not MO.db.settings.replaceAutocomplete)
end

local function Pick(contact)
	SendMailNameEditBox:SetText(Contacts.MailName(contact))
	SendMailNameEditBox:SetCursorPosition(#SendMailNameEditBox:GetText())
	suggestFrame:Hide()
	if SendMailSubjectEditBox then
		SendMailSubjectEditBox:SetFocus()
	end
end

local function UpdateHighlight()
	for i, button in ipairs(suggestFrame.buttons) do
		button.selected:SetShown(i == selectedIndex)
	end
end

local function UpdateSuggestions()
	local box = SendMailNameEditBox
	local text = box:GetText()
	results = (box:HasFocus() and text ~= "") and Contacts.Search(text, MAX_SUGGESTIONS) or {}
	-- Hide when the box already holds exactly the only match.
	if #results == 1 and Names.Equal(Contacts.MailName(results[1]), text) then
		results = {}
	end
	if #results == 0 then
		suggestFrame:Hide()
		return
	end
	selectedIndex = 1
	for i, button in ipairs(suggestFrame.buttons) do
		local contact = results[i]
		if contact then
			local label = Names.ClassColored(Contacts.DisplayName(contact), contact.class)
			if not Contacts.SameFaction(contact) then
				label = label .. " |cffff5555(" .. contact.faction .. ")|r"
			end
			button.text:SetText(label)
			button.contact = contact
			button:Show()
		else
			button:Hide()
		end
	end
	suggestFrame:SetHeight(#results * 18 + 10)
	suggestFrame:Show()
	UpdateHighlight()
end

local function CreateSuggestFrame()
	suggestFrame = CreateFrame("Frame", "MailOverhaulSuggestFrame", SendMailFrame, "TooltipBackdropTemplate")
	suggestFrame:SetFrameStrata("DIALOG")
	suggestFrame:SetPoint("TOPLEFT", SendMailNameEditBox, "BOTTOMLEFT", -6, 0)
	suggestFrame:SetWidth(240)
	suggestFrame:Hide()
	suggestFrame.buttons = {}
	for i = 1, MAX_SUGGESTIONS do
		local button = CreateFrame("Button", nil, suggestFrame)
		W.StyleRow(button)
		button:SetHeight(18)
		button:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 18)
		button:SetPoint("RIGHT", -5, 0)
		button:SetScript("OnClick", function(self)
			Pick(self.contact)
		end)
		button:SetScript("OnEnter", function()
			selectedIndex = i
			UpdateHighlight()
		end)
		suggestFrame.buttons[i] = button
	end
end

-- Wrap a script so our list handles the key first while it's visible.
local function WrapScript(box, scriptName, handler)
	local original = box:GetScript(scriptName)
	box:SetScript(scriptName, function(self, ...)
		if suggestFrame:IsShown() and handler(self, ...) then
			return
		end
		if original then
			return original(self, ...)
		end
	end)
end

local function HookNameBox()
	local box = SendMailNameEditBox
	box:HookScript("OnTextChanged", function(_, userInput)
		if userInput then
			UpdateSuggestions()
		end
	end)
	box:HookScript("OnEditFocusLost", function()
		-- Delay so a click on a suggestion lands before the list hides.
		C_Timer.After(0.15, function()
			if not box:HasFocus() then
				suggestFrame:Hide()
			end
		end)
	end)
	local function Accept()
		local contact = results[selectedIndex]
		if contact then
			Pick(contact)
			return true
		end
	end
	WrapScript(box, "OnTabPressed", Accept)
	WrapScript(box, "OnEnterPressed", Accept)
	WrapScript(box, "OnEscapePressed", function()
		suggestFrame:Hide()
		return true
	end)
	WrapScript(box, "OnArrowPressed", function(_, key)
		if key == "UP" then
			selectedIndex = selectedIndex > 1 and selectedIndex - 1 or #results
		elseif key == "DOWN" then
			selectedIndex = selectedIndex < #results and selectedIndex + 1 or 1
		else
			return false
		end
		UpdateHighlight()
		return true
	end)
end

local function CreateAddressButton()
	local button = CreateFrame("Button", nil, SendMailFrame)
	button:SetSize(22, 22)
	button:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 2, 0)
	button:SetNormalTexture("Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon")
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnClick", function(self)
		W.Menu(self, function(_, root)
			W.AddContactMenu(root, Pick)
			root:CreateDivider()
			root:CreateButton("Edit address book...", function()
				MO.Mailbox.Show("contacts")
			end)
		end)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Address book")
		GameTooltip:AddLine("Pick an alt or contact.", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
end

-- Button on Blizzard's window to switch to the MailOverhaul mailbox.
local function CreateSwitchButton()
	local anchor = MailFrameTab2 or (MailFrame.Tabs and MailFrame.Tabs[2])
	local button = W.Button(MailFrame, "Mail Overhaul", 110, function()
		MO.Mailbox.SetEnabled(true)
	end)
	if anchor then
		button:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
	else
		button:SetPoint("TOPRIGHT", MailFrame, "BOTTOMRIGHT", 0, -2)
	end
end

function MailHooks.Init()
	if not (SendMailFrame and SendMailNameEditBox) then
		MO.Print("Couldn't find the Send Mail frame; mail features are disabled.")
		return
	end
	CreateSuggestFrame()
	HookNameBox()
	CreateAddressButton()
	CreateSwitchButton()
	MailHooks.ApplySettings()
end
