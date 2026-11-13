local _, ns = ...
local MO = ns.Modules.MailOverhaul

--[[ Inbox tab: mail list on the left, the selected mail on the right.
Taking items/money is asynchronous; "Open all" takes one thing at a time and
waits for the server (C_Mail.IsCommandPending) between requests, like Blizzard's.
]]
local InboxTab = {}
MO.InboxTab = InboxTab

local W = MO.Widgets
local Names = MO.Names
local Contacts = MO.Contacts

local ATTACHMENTS_MAX = ATTACHMENTS_MAX_RECEIVE or 16
local OPEN_DELAY = 0.15

local page, list
local selectedIndex
local detail = {}

StaticPopupDialogs["MAILOVERHAUL_COD"] = {
	text = "Pay %s C.O.D. to take this item?",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function(_, data)
		TakeInboxItem(data.mail, data.attachment)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["MAILOVERHAUL_DELETE"] = {
	text = "This mail still has items or gold. Delete it anyway?",
	button1 = DELETE,
	button2 = CANCEL,
	OnAccept = function(_, data)
		DeleteInboxItem(data.mail)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
}

local function Header(index)
	local packageIcon, stationeryIcon, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned,
		textCreated, canReply, isGM = GetInboxHeaderInfo(index)
	return {
		index = index,
		icon = packageIcon or stationeryIcon,
		sender = sender,
		subject = subject or "",
		money = money or 0,
		cod = cod or 0,
		daysLeft = daysLeft or 0,
		itemCount = itemCount or 0,
		wasRead = wasRead,
		wasReturned = wasReturned,
		canReply = canReply,
		isGM = isGM,
	}
end

local function SenderText(mail)
	if not mail.sender then
		return "|cff999999Unknown|r"
	end
	local contact = Contacts.FindByName(mail.sender)
	return Names.ClassColored(mail.sender, contact and contact.class)
end

local function DaysText(days)
	if days >= 1 then
		local text = ("%d day%s"):format(days, days >= 2 and "s" or "")
		return days < 3 and ("|cffff5555" .. text .. "|r") or text
	end
	return "|cffff5555< 1 day|r"
end

---------------------------------------------------------------------------
-- Open all
---------------------------------------------------------------------------
local opener = CreateFrame("Frame")
opener:Hide()
local openState -- { mail, attachment, wait, failed = { [itemID] = true } }

local function StopOpening(message)
	openState = nil
	opener:Hide()
	if C_Mail.SetOpeningAll then
		C_Mail.SetOpeningAll(false)
	end
	MO.Fire("INBOX_OPENING", false, message)
end

-- Finds the next (mail, attachment-or-"money") to take, starting from the current position.
local function NextTarget()
	local num = GetInboxNumItems()
	while openState.mail <= num do
		local mail = Header(openState.mail)
		local skip = mail.isGM or mail.cod > 0
		if not skip then
			if mail.money > 0 then
				return openState.mail, "money"
			end
			if mail.itemCount > 0 then
				for a = 1, ATTACHMENTS_MAX do
					local _, itemID = GetInboxItem(openState.mail, a)
					if itemID and not openState.failed[itemID] then
						return openState.mail, a
					end
				end
			end
		end
		openState.mail = openState.mail + 1
	end
	return nil
end

--[[ One request at a time, driven by the server's replies:
  ready    -> send the next take request
  waiting  -> until MAIL_SUCCESS / MAIL_FAILED (or REPLY_TIMEOUT)
  settling -> until the inbox data has refreshed (MAIL_INBOX_UPDATE, or SETTLE_TIMEOUT),
              no command is pending, and OPEN_DELAY has passed
Sending on a timer alone can act on stale inbox data and ask for an attachment
or gold that's already been taken ("item not found" / mail database errors). ]]
local REPLY_TIMEOUT = 5
local SETTLE_TIMEOUT = 1.5

local function SetPhase(phase)
	openState.phase = phase
	openState.elapsed = 0
	if phase == "waiting" then
		-- Only inbox updates after this request count as "refreshed".
		openState.inboxUpdated = false
	end
end

opener:SetScript("OnUpdate", function(_, elapsed)
	if not openState then
		opener:Hide()
		return
	end
	openState.elapsed = openState.elapsed + elapsed

	if openState.phase == "waiting" then
		if openState.elapsed < REPLY_TIMEOUT then
			return
		end
		-- No reply: don't retry the same thing forever.
		local target = openState.target
		if target.itemID then
			openState.failed[target.itemID] = true
		else
			openState.mail = openState.mail + 1
		end
		SetPhase("settling")
		return
	end

	if openState.phase == "settling" then
		local settled = openState.inboxUpdated or openState.elapsed >= SETTLE_TIMEOUT
		if not settled or openState.elapsed < OPEN_DELAY or C_Mail.IsCommandPending() then
			return
		end
		SetPhase("ready")
	end

	-- ready
	if C_Mail.IsCommandPending() then
		return
	end
	local mailIndex, what = NextTarget()
	if not mailIndex then
		StopOpening("Done.")
		return
	end
	if what == "money" then
		openState.target = { mail = mailIndex }
		SetPhase("waiting")
		TakeInboxMoney(mailIndex)
	else
		if C_Container.CalculateTotalNumberOfFreeBagSlots() == 0 then
			StopOpening("Your bags are full.")
			return
		end
		local _, itemID = GetInboxItem(mailIndex, what)
		openState.target = { mail = mailIndex, attachment = what, itemID = itemID }
		SetPhase("waiting")
		TakeInboxItem(mailIndex, what)
	end
end)

local function StartOpening()
	openState = { mail = 1, failed = {} }
	SetPhase("ready")
	if C_Mail.SetOpeningAll then
		C_Mail.SetOpeningAll(true)
	end
	opener:Show()
	MO.Fire("INBOX_OPENING", true)
end

function InboxTab.IsOpening()
	return openState ~= nil
end

opener:RegisterEvent("MAIL_SUCCESS")
opener:RegisterEvent("MAIL_FAILED")
opener:RegisterEvent("MAIL_INBOX_UPDATE")
opener:RegisterEvent("MAIL_CLOSED")
opener:RegisterEvent("MAIL_OPEN_ALL_CANCELED")
opener:SetScript("OnEvent", function(_, event, itemID)
	if not openState then
		return
	end
	if event == "MAIL_SUCCESS" then
		if openState.phase == "waiting" then
			SetPhase("settling")
		end
	elseif event == "MAIL_FAILED" then
		if itemID then
			openState.failed[itemID] = true
		elseif openState.phase == "waiting" and openState.target and openState.target.itemID then
			openState.failed[openState.target.itemID] = true
		end
		if openState.phase == "waiting" then
			SetPhase("settling")
		end
	elseif event == "MAIL_INBOX_UPDATE" then
		openState.inboxUpdated = true
	elseif event == "MAIL_CLOSED" then
		StopOpening(nil)
	elseif event == "MAIL_OPEN_ALL_CANCELED" then
		StopOpening("Canceled by the server.")
	end
end)

---------------------------------------------------------------------------
-- Detail pane
---------------------------------------------------------------------------
local function TakeAttachment(mailIndex, attachment)
	local mail = Header(mailIndex)
	if mail.cod > 0 then
		local dialog = StaticPopup_Show("MAILOVERHAUL_COD", GetMoneyString(mail.cod))
		if dialog then
			dialog.data = { mail = mailIndex, attachment = attachment }
		end
	else
		TakeInboxItem(mailIndex, attachment)
	end
end

local function BuildDetail(parent)
	local pane = CreateFrame("Frame", nil, parent)
	detail.pane = pane

	detail.from = W.Label(pane, "", "GameFontNormalLarge")
	detail.from:SetPoint("TOPLEFT", 4, -2)
	detail.from:SetPoint("RIGHT", -4, 0)
	detail.subject = W.Label(pane, "", "GameFontHighlight")
	detail.subject:SetPoint("TOPLEFT", detail.from, "BOTTOMLEFT", 0, -6)
	detail.subject:SetPoint("RIGHT", -4, 0)
	detail.meta = W.Label(pane, "", "GameFontHighlightSmall")
	detail.meta:SetPoint("TOPLEFT", detail.subject, "BOTTOMLEFT", 0, -4)
	detail.meta:SetTextColor(0.7, 0.7, 0.7)

	local bodyFrame = CreateFrame("ScrollFrame", nil, pane, "ScrollFrameTemplate")
	bodyFrame:SetPoint("TOPLEFT", detail.meta, "BOTTOMLEFT", 0, -10)
	bodyFrame:SetPoint("RIGHT", -24, 0)
	bodyFrame:SetHeight(150)
	local bodyChild = CreateFrame("Frame", nil, bodyFrame)
	bodyChild:SetSize(1, 1)
	bodyFrame:SetScrollChild(bodyChild)
	detail.body = W.Label(bodyChild, "", "GameFontHighlight")
	detail.body:SetPoint("TOPLEFT")
	detail.body:SetJustifyV("TOP")
	detail.body:SetSpacing(2)
	bodyFrame:SetScript("OnSizeChanged", function(_, width)
		bodyChild:SetWidth(width)
		detail.body:SetWidth(width)
	end)
	detail.bodyChild = bodyChild

	detail.moneyLine = W.Label(pane, "", "GameFontHighlight")
	detail.moneyLine:SetPoint("TOPLEFT", bodyFrame, "BOTTOMLEFT", 0, -12)
	detail.takeMoney = W.Button(pane, "Take gold", 90, function()
		if selectedIndex then
			TakeInboxMoney(selectedIndex)
		end
	end)
	detail.takeMoney:SetPoint("LEFT", detail.moneyLine, "RIGHT", 10, 0)

	detail.slots = {}
	for i = 1, ATTACHMENTS_MAX do
		local slot = W.ItemSlot(pane, 40)
		local col, rowIndex = (i - 1) % 6, math.floor((i - 1) / 6)
		slot:SetPoint("TOPLEFT", detail.moneyLine, "BOTTOMLEFT", col * 44, -12 - rowIndex * 44)
		slot:SetScript("OnClick", function(self)
			if not selectedIndex then
				return
			end
			if IsModifiedClick("CHATLINK") and GetInboxItemLink then
				ChatFrameUtil.InsertLink(GetInboxItemLink(selectedIndex, self.attachment))
				return
			end
			TakeAttachment(selectedIndex, self.attachment)
		end)
		slot:SetScript("OnEnter", function(self)
			if selectedIndex and self.attachment then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetInboxItem(selectedIndex, self.attachment)
				GameTooltip:Show()
			end
		end)
		detail.slots[i] = slot
	end

	local takeAll = W.Button(pane, "Take all", 90, function()
		if not selectedIndex then
			return
		end
		local mail = Header(selectedIndex)
		if mail.cod > 0 then
			for a = 1, ATTACHMENTS_MAX do
				if GetInboxItem(selectedIndex, a) then
					TakeAttachment(selectedIndex, a)
					return
				end
			end
		end
		AutoLootMailItem(selectedIndex)
	end)
	takeAll:SetPoint("BOTTOMLEFT", 0, 0)
	local reply = W.Button(pane, "Reply", 80, function()
		local mail = selectedIndex and Header(selectedIndex)
		if mail and mail.sender then
			local subject = mail.subject:find("^RE:") and mail.subject or ("RE: " .. mail.subject)
			MO.SendTab.ComposeTo(mail.sender, subject)
		end
	end)
	reply:SetPoint("LEFT", takeAll, "RIGHT", 4, 0)
	local deleteButton = W.Button(pane, "Delete", 80, function()
		if not selectedIndex then
			return
		end
		if InboxItemCanDelete(selectedIndex) then
			local mail = Header(selectedIndex)
			if mail.money > 0 or mail.itemCount > 0 then
				local dialog = StaticPopup_Show("MAILOVERHAUL_DELETE")
				if dialog then
					dialog.data = { mail = selectedIndex }
				end
			else
				DeleteInboxItem(selectedIndex)
			end
		else
			ReturnInboxItem(selectedIndex)
		end
	end)
	deleteButton:SetPoint("LEFT", reply, "RIGHT", 4, 0)
	detail.takeAll, detail.reply, detail.delete = takeAll, reply, deleteButton

	detail.empty = W.Label(parent, "Select a mail.", "GameFontDisable")
	detail.empty:SetPoint("CENTER", pane, "CENTER")
	return pane
end

local function RefreshDetail()
	local num = GetInboxNumItems()
	if not selectedIndex or selectedIndex > num then
		selectedIndex = nil
		detail.pane:Hide()
		detail.empty:SetShown(true)
		return
	end
	detail.pane:Show()
	detail.empty:Hide()

	local mail = Header(selectedIndex)
	-- GetInboxText marks the mail read, which is a server request. Only call it when
	-- the selection changes, not on every inbox update (that collides with Open all).
	local textKey = ("%d\001%s\001%s"):format(selectedIndex, mail.sender or "", mail.subject)
	if detail.textKey ~= textKey then
		detail.textKey = textKey
		local bodyText, _, _, _, isInvoice = GetInboxText(selectedIndex)
		if isInvoice and GetInboxInvoiceInfo then
			local invoiceType, itemName, playerName, bid = GetInboxInvoiceInfo(selectedIndex)
			if invoiceType and itemName then
				bodyText = ("%s: %s%s%s"):format(invoiceType, itemName,
					playerName and ("\nPlayer: " .. playerName) or "",
					(bid and bid > 0) and ("\nAmount: " .. GetMoneyString(bid)) or "")
			end
		end
		detail.bodyText = bodyText or ""
	end
	local bodyText = detail.bodyText

	detail.from:SetText(SenderText(mail))
	detail.subject:SetText(mail.subject)
	local meta = { DaysText(mail.daysLeft) .. " left" }
	if mail.wasReturned then
		table.insert(meta, "returned")
	end
	if mail.cod > 0 then
		table.insert(meta, "|cffff5555C.O.D. " .. GetMoneyString(mail.cod) .. "|r")
	end
	detail.meta:SetText(table.concat(meta, "  -  "))
	detail.body:SetText(bodyText or "")
	detail.bodyChild:SetHeight(math.max(1, detail.body:GetStringHeight()))

	local hasMoney = mail.money > 0
	detail.moneyLine:SetText(hasMoney and ("Gold: " .. GetMoneyString(mail.money)) or "")
	detail.takeMoney:SetShown(hasMoney)

	local shown = 0
	for a = 1, ATTACHMENTS_MAX do
		local name, itemID, texture, count, quality = GetInboxItem(selectedIndex, a)
		if name then
			shown = shown + 1
			local slot = detail.slots[shown]
			slot.attachment = a
			W.SetItemSlot(slot, texture, count, quality, itemID)
			slot:Show()
		end
	end
	for i = shown + 1, ATTACHMENTS_MAX do
		detail.slots[i]:Hide()
	end

	-- Manual takes during Open all would race it for the same mail.
	detail.takeAll:SetEnabled((shown > 0 or hasMoney) and not openState)
	detail.takeMoney:SetEnabled(not openState)
	detail.reply:SetEnabled(mail.canReply and mail.sender ~= nil)
	detail.delete:SetText(InboxItemCanDelete(selectedIndex) and DELETE or MAIL_RETURN)
end

---------------------------------------------------------------------------
-- Tab
---------------------------------------------------------------------------
function InboxTab.Build(tabPage)
	page = tabPage

	-- Header: Open all + counts + check for more.
	local openAll = W.Button(page.header, "Open all", 100)
	openAll:SetPoint("LEFT", 8, 0)
	local counts = W.Label(page.header, "", "GameFontHighlightSmall")
	counts:SetPoint("LEFT", openAll, "RIGHT", 12, 0)
	local checkMore = W.Button(page.header, "Check for more", 120, function()
		CheckInbox()
	end)
	checkMore:SetPoint("LEFT", counts, "RIGHT", 10, 0)

	openAll:SetScript("OnClick", function()
		if openState then
			StopOpening("Stopped.")
		else
			StartOpening()
		end
	end)
	openAll:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Open all")
		GameTooltip:AddLine("Takes all gold and items. C.O.D. and GM mail are skipped.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	openAll:SetScript("OnLeave", GameTooltip_Hide)

	-- Mail list.
	local function Build(row)
		W.StyleRow(row)
		row.text:Hide()
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(32, 32)
		row.icon:SetPoint("LEFT", 4, 0)
		row.sender = W.Label(row, "", "GameFontNormal")
		row.sender:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
		row.sender:SetPoint("RIGHT", -90, 0)
		row.sender:SetWordWrap(false)
		row.subject = W.Label(row, "", "GameFontHighlightSmall")
		row.subject:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
		row.subject:SetPoint("RIGHT", -90, 0)
		row.subject:SetWordWrap(false)
		row.right1 = W.Label(row, "", "GameFontHighlightSmall")
		row.right1:SetPoint("TOPRIGHT", -6, -5)
		row.right1:SetJustifyH("RIGHT")
		row.right2 = W.Label(row, "", "GameFontHighlightSmall")
		row.right2:SetPoint("BOTTOMRIGHT", -6, 5)
		row.right2:SetJustifyH("RIGHT")
	end

	local function Update(row, mail)
		row.selected:SetShown(mail.index == selectedIndex)
		row.icon:SetTexture(mail.icon or "Interface\\Icons\\INV_Letter_15")
		row.icon:SetDesaturated(mail.wasRead and mail.itemCount == 0 and mail.money == 0)
		row.sender:SetText(SenderText(mail))
		row.subject:SetText(mail.subject)
		row.subject:SetTextColor(mail.wasRead and 0.6 or 1, mail.wasRead and 0.6 or 1, mail.wasRead and 0.6 or 1)
		local right = {}
		if mail.cod > 0 then
			table.insert(right, "|cffff5555COD|r")
		elseif mail.money > 0 then
			table.insert(right, GetMoneyString(mail.money))
		end
		if mail.itemCount > 0 then
			table.insert(right, mail.itemCount .. (mail.itemCount == 1 and " item" or " items"))
		end
		row.right1:SetText(table.concat(right, " "))
		row.right2:SetText(DaysText(mail.daysLeft))
		row:SetScript("OnClick", function()
			selectedIndex = mail.index
			list:RefreshRows()
			RefreshDetail()
		end)
	end

	list = W.List(page, 44, Build, Update)
	list:SetPoint("TOPLEFT", 0, 0)
	list:SetPoint("BOTTOMLEFT", 0, 0)
	list:SetWidth(360)

	local divider = page:CreateTexture(nil, "ARTWORK")
	divider:SetWidth(1)
	divider:SetPoint("TOPLEFT", list, "TOPRIGHT", 10, 0)
	divider:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 10, 0)
	divider:SetColorTexture(1, 0.82, 0, 0.25)

	local pane = BuildDetail(page)
	pane:SetPoint("TOPLEFT", list, "TOPRIGHT", 20, 0)
	pane:SetPoint("BOTTOMRIGHT", 0, 0)

	local empty = W.Label(page, "", "GameFontDisable")
	empty:SetPoint("CENTER", list, "CENTER")

	local lastNum = 0
	function page:Refresh()
		local num, total = GetInboxNumItems()
		-- A mail was removed: indexes shifted, so don't silently open (and mark read) a different one.
		if num < lastNum then
			selectedIndex = nil
		end
		lastNum = num
		local mails = {}
		for i = 1, num do
			mails[i] = Header(i)
		end
		list:SetData(mails)
		empty:SetText(num == 0 and "Your inbox is empty." or "")
		if total and total > num then
			counts:SetText(("%d shown, %d more on the server"):format(num, total - num))
		else
			counts:SetText(("%d mail"):format(num))
		end
		checkMore:SetShown(total ~= nil and total > num)
		checkMore:SetEnabled(not C_Mail.CanCheckInbox or C_Mail.CanCheckInbox())
		openAll:SetText(openState and "Stop" or "Open all")
		openAll:SetEnabled(num > 0 or openState ~= nil)
		RefreshDetail()
	end

	local pending = false
	local events = CreateFrame("Frame", nil, page)
	events:RegisterEvent("MAIL_INBOX_UPDATE")
	events:RegisterEvent("MAIL_SHOW")
	events:SetScript("OnEvent", function(_, event)
		if event == "MAIL_SHOW" then
			selectedIndex = nil
		end
		if pending or not page:IsVisible() then
			return
		end
		pending = true
		C_Timer.After(0.05, function()
			pending = false
			if page:IsVisible() then
				page:Refresh()
			end
		end)
	end)

	MO.On("INBOX_OPENING", function(_, message)
		if message then
			MO.Print("Open all: %s", message)
		end
		if page:IsVisible() then
			page:Refresh()
		end
	end)
	page:HookScript("OnHide", function()
		if openState then
			StopOpening(nil)
		end
	end)
end
