local _, ns = ...
local MO = ns.Modules.MailOverhaul

--[[ The MailOverhaul mailbox window: a portrait frame with icon tabs down the
right side, like Forever's character and profession windows.

How it takes over from Blizzard's window (compare TradeSkillMaster, which
lets Blizzard's MailFrame open and then hides it):
  * Forever opens MailFrame through the player interaction manager
    (RegisterPlayerInteraction(MailInfo, { showFunc = MailFrame_Show })), not MAIL_SHOW.
    We add a showCondition so the manager simply doesn't show it while MailOverhaul is on.
  * We track the mailbox ourselves from PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE,
    and call CloseMail() when our window closes.
  * The mail session doesn't need MailFrame shown; Blizzard's frame stays hidden.
  * Switching from Blizzard's window to ours mid-visit hides MailFrame without
    closing the mailbox (its OnHide normally calls CloseMail).
Inbox and Send only work at a mailbox; Rules and Address Book work anywhere.
]]
local Mailbox = {}
MO.Mailbox = Mailbox

local W = MO.Widgets

local frame
local tabs = {}      -- [key] = { tab, page, title, needsMailbox }
local tabOrder = {}
local currentKey
local mailOpen = false       -- the player is at a mailbox
local keepSessionOnHide = false -- hide a window without ending the mailbox visit

local MAIL_INTERACTION = Enum.PlayerInteractionType and Enum.PlayerInteractionType.MailInfo

local TABS = {
	{ key = "inbox", title = "Inbox", icon = "Interface\\Icons\\INV_Letter_15", needsMailbox = true },
	{ key = "send", title = "Send Mail", icon = "Interface\\Icons\\INV_Misc_Note_01", needsMailbox = true },
	{ key = "rules", title = "Mail Rules", icon = "Interface\\Icons\\INV_Misc_Gear_01" },
	{ key = "contacts", title = "Address Book", icon = "Interface\\Icons\\INV_Misc_Book_09" },
}

function Mailbox.AtMailbox()
	return mailOpen
end

local function UsingOurs()
	return MO.db.settings.useMailbox
end

local function UpdateTabs()
	for _, key in ipairs(tabOrder) do
		local entry = tabs[key]
		local usable = mailOpen or not entry.needsMailbox
		entry.tab:SetChecked(key == currentKey)
		entry.tab.Icon:SetDesaturated(not usable)
		entry.tab.tooltipText = usable and entry.title or (entry.title .. "\n|cff999999Open a mailbox to use this.|r")
	end
end

function Mailbox.SelectTab(key)
	local entry = tabs[key]
	if not entry then
		return
	end
	if entry.needsMailbox and not mailOpen then
		return
	end
	currentKey = key
	for otherKey, other in pairs(tabs) do
		other.page:SetShown(otherKey == key)
	end
	frame:SetTitle(entry.title)
	if entry.page.Refresh then
		entry.page:Refresh()
	end
	UpdateTabs()
end

function Mailbox.CurrentTab()
	return currentKey
end

local function Create()
	frame = CreateFrame("Frame", "MailOverhaulMailbox", UIParent, "ButtonFrameTemplate")
	frame:SetSize(720, 560)
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	table.insert(UISpecialFrames, "MailOverhaulMailbox")

	ButtonFrameTemplate_HideButtonBar(frame)
	frame:SetPortraitToAsset("Interface\\Icons\\INV_Letter_15")
	frame.Inset:SetPoint("TOPLEFT", 4, -60)

	-- Switch to Blizzard's window.
	local blizzButton = W.Button(frame, "Blizzard UI", 96, function()
		Mailbox.SetEnabled(false)
	end)
	blizzButton:SetPoint("TOPRIGHT", -10, -30)
	blizzButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Use Blizzard's mail window")
		GameTooltip:AddLine("Switch back any time with the Mail Overhaul button on it, or /mo blizz.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	blizzButton:SetScript("OnLeave", GameTooltip_Hide)
	frame.blizzButton = blizzButton

	local builders = {
		inbox = MO.InboxTab.Build,
		send = MO.SendTab.Build,
		rules = MO.RulesTab.Build,
		contacts = MO.AddressBookTab.Build,
	}

	local previous
	for _, def in ipairs(TABS) do
		local tab = CreateFrame("Frame", nil, frame, "LargeSideTabButtonTemplate")
		tab:SetFillToInterior(true)
		tab.Icon:SetTexture(def.icon)
		tab:UpdateIconInterior()
		tab.tooltipText = def.title
		if previous then
			tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
		else
			tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -60)
		end
		tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
			if button == "LeftButton" and upInside then
				Mailbox.SelectTab(def.key)
			end
		end)
		previous = tab

		-- Pages fill the inset; the strip above it (the "header") holds tab-specific controls.
		local page = CreateFrame("Frame", nil, frame)
		page:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 8, -8)
		page:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -8, 8)
		page:Hide()
		local header = CreateFrame("Frame", nil, page)
		header:SetPoint("TOPLEFT", frame, "TOPLEFT", 64, -26)
		header:SetPoint("BOTTOMRIGHT", frame.Inset, "TOPRIGHT", -112, 2)
		page.header = header

		builders[def.key](page)
		tabs[def.key] = { tab = tab, page = page, title = def.title, needsMailbox = def.needsMailbox }
		table.insert(tabOrder, def.key)
	end

	frame:SetScript("OnHide", function()
		if keepSessionOnHide or not mailOpen then
			return
		end
		-- Closing our window ends the mailbox visit.
		CloseAllBags(frame)
		CloseMail()
	end)
end

function Mailbox.Show(key)
	if not frame then
		Create()
	end
	frame.blizzButton:SetShown(mailOpen)
	frame:Show()
	if not key or not tabs[key] or (tabs[key].needsMailbox and not mailOpen) then
		key = mailOpen and "inbox" or (key == "rules" and "rules" or "contacts")
	end
	Mailbox.SelectTab(key)
end

-- Hides our window without ending the mailbox visit.
local function HideKeepingSession()
	if frame and frame:IsShown() then
		keepSessionOnHide = true
		frame:Hide()
		keepSessionOnHide = false
	end
end

local function HideBlizzardKeepingSession()
	if MailFrame and MailFrame:IsShown() then
		keepSessionOnHide = true
		HideUIPanel(MailFrame)
		keepSessionOnHide = false
	end
end

local function ShowOurs()
	Mailbox.Show("inbox")
	OpenAllBags(frame)
	if not C_Mail.CanCheckInbox or C_Mail.CanCheckInbox() then
		CheckInbox()
	end
end

local function ShowBlizzard()
	if MailFrame_Show then
		MailFrame_Show()
	else
		ShowUIPanel(MailFrame)
	end
end

-- Turns the replacement window on/off. Takes effect immediately if at a mailbox.
function Mailbox.SetEnabled(enabled)
	MO.db.settings.useMailbox = enabled
	if mailOpen then
		if enabled then
			HideBlizzardKeepingSession()
			ShowOurs()
		else
			HideKeepingSession()
			ShowBlizzard()
		end
	end
	MO.Fire("MAILBOX_MODE_CHANGED", enabled)
end

local function OnMailboxOpened()
	mailOpen = true
	if UsingOurs() then
		ShowOurs()
	end
	-- Otherwise Blizzard's interaction manager shows MailFrame itself.
end

local function OnMailboxClosed()
	if not mailOpen then
		return
	end
	mailOpen = false
	if frame and frame:IsShown() then
		-- Stay open only on a tab that works without a mailbox.
		if tabs[currentKey] and tabs[currentKey].needsMailbox then
			frame:Hide()
		else
			CloseAllBags(frame)
			frame.blizzButton:Hide()
			UpdateTabs()
		end
	end
end

-- Called when Blizzard_MailFrame is loaded.
function Mailbox.Init()
	-- Don't let Blizzard's interaction manager open MailFrame while ours is in use.
	if MAIL_INTERACTION and SetPlayerInteractionConditions then
		SetPlayerInteractionConditions(MAIL_INTERACTION, {
			showCondition = function()
				return not UsingOurs()
			end,
		})
	end

	-- MailFrame's OnHide calls CloseMail. When we're only swapping windows, do its
	-- cleanup without ending the visit.
	local blizzardOnHide = MailFrame:GetScript("OnHide")
	MailFrame:SetScript("OnHide", function(self, ...)
		if keepSessionOnHide then
			if OpenMailFrame then
				HideUIPanel(OpenMailFrame)
			end
			SendMailNameEditBox:SetText("")
			SendMailSubjectEditBox:SetText("")
			SendMailBodyEditBox:SetText("")
			SetSendMailShowing(false)
			return
		end
		if blizzardOnHide then
			return blizzardOnHide(self, ...)
		end
	end)

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
	events:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
	events:RegisterEvent("MAIL_CLOSED")
	events:SetScript("OnEvent", function(_, event, interactionType)
		if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
			if interactionType == MAIL_INTERACTION then
				OnMailboxOpened()
			end
		elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
			if interactionType == MAIL_INTERACTION then
				OnMailboxClosed()
			end
		elseif event == "MAIL_CLOSED" then
			OnMailboxClosed()
		end
	end)
end
