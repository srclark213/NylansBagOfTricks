local _, ns = ...
local MO = ns.Modules.MailOverhaul

--[[ Send tab. Three views:
  people  - search, "Send by rules", and a list of recent people, alts and contacts.
            Clicking a person opens compose.
  compose - recipient, subject, body, money/COD, 12 attachment slots, and the
            items your rules route to this person.
  plan    - "Send by rules" preview for everyone; Start queues the mails, and each
            one opens in compose for a one-click send.
]]
local SendTab = {}
MO.SendTab = SendTab

local W = MO.Widgets
local Names = MO.Names
local Contacts = MO.Contacts
local Rules = MO.Rules
local Sender = MO.Sender

local page
local views = {}
local currentView = "people"

local function ShowView(name)
	currentView = name
	for key, view in pairs(views) do
		view:SetShown(key == name)
		view.header:SetShown(key == name)
	end
	if views[name].Refresh then
		views[name]:Refresh()
	end
	SetSendMailShowing(name == "compose")
end

-- Shared: items the rules would send, keyed by recipient. Rebuilt on demand.
local plan
local function RebuildPlan()
	plan = Rules.BuildPlan()
	local byKey = {}
	for _, group in ipairs(plan.groups) do
		byKey[Names.Key(group.recipient)] = group
	end
	plan.byKey = byKey
	return plan
end

local function PlanGroupFor(name)
	return plan and plan.byKey and plan.byKey[Names.Key(name)]
end

local function NewView()
	local view = CreateFrame("Frame", nil, page)
	view:SetAllPoints()
	view:Hide()
	view.header = CreateFrame("Frame", nil, page.header)
	view.header:SetAllPoints()
	view.header:Hide()
	return view
end

---------------------------------------------------------------------------
-- People view
---------------------------------------------------------------------------
local OpenCompose -- forward

local function BuildPeopleView()
	local view = NewView()
	views.people = view

	local search = W.SearchBox(view.header, 200, "Search people")
	search:SetPoint("LEFT", 8, 0)

	local rulesButton = W.Button(view.header, "Send by rules", 150, function()
		ShowView("plan")
	end)
	rulesButton:SetPoint("LEFT", search, "RIGHT", 10, 0)

	local otherButton = W.Button(view.header, "Other name...", 110, function()
		OpenCompose(nil, nil)
	end)
	otherButton:SetPoint("LEFT", rulesButton, "RIGHT", 6, 0)

	local function Extent(entry)
		return entry.header and 26 or 42
	end

	local function Build(row)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(30, 30)
		row.icon:SetPoint("LEFT", 6, 0)
		row.name = W.Label(row, "", "GameFontNormal")
		row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
		row.sub = W.Label(row, "", "GameFontHighlightSmall")
		row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
		row.sub:SetTextColor(0.7, 0.7, 0.7)
		row.badge = W.Label(row, "", "GameFontNormalSmall")
		row.badge:SetPoint("RIGHT", -10, 0)
		row.badge:SetJustifyH("RIGHT")
		row.headerText = W.Label(row, "", "GameFontNormalLarge")
		row.headerText:SetPoint("BOTTOMLEFT", 4, 4)
		row.line = row:CreateTexture(nil, "ARTWORK")
		row.line:SetHeight(1)
		row.line:SetPoint("BOTTOMLEFT", 2, 1)
		row.line:SetPoint("BOTTOMRIGHT", -2, 1)
		row.line:SetColorTexture(1, 0.82, 0, 0.3)
	end

	local function Update(row, entry)
		local isHeader = entry.header ~= nil
		row.headerText:SetShown(isHeader)
		row.line:SetShown(isHeader)
		row.icon:SetShown(not isHeader)
		row.name:SetShown(not isHeader)
		row.sub:SetShown(not isHeader)
		row.badge:SetShown(not isHeader)
		row:EnableMouse(not isHeader)
		if isHeader then
			row.headerText:SetText(entry.header)
			row:SetScript("OnClick", nil)
			return
		end

		local contact = entry.contact
		W.SetClassIcon(row.icon, contact and contact.class)
		row.name:SetText(Names.ClassColored(entry.name, contact and contact.class))

		local parts = {}
		if contact then
			if contact.nickname then
				table.insert(parts, contact.nickname)
			end
			if contact.kind == "alt" then
				table.insert(parts, contact.level and ("Level " .. contact.level .. " alt") or "Alt")
				local seen = W.Ago(contact.lastSeen)
				if seen then
					table.insert(parts, "seen " .. seen)
				end
			elseif contact.note then
				table.insert(parts, contact.note)
			end
			if not Contacts.SameFaction(contact) then
				table.insert(parts, "|cffff5555" .. contact.faction .. "|r")
			end
		end
		if entry.sentAt then
			table.insert(parts, "mailed " .. W.Ago(entry.sentAt))
		end
		row.sub:SetText(table.concat(parts, "  -  "))

		local group = PlanGroupFor(entry.name)
		row.badge:SetText(group and ("|cff40ff40%d item(s) by rules|r"):format(#group.items) or "")
		row:SetScript("OnClick", function()
			OpenCompose(entry.name, contact)
		end)
	end

	local list = W.List(view, Extent, Build, Update)
	list:SetPoint("TOPLEFT", 0, 0)
	list:SetPoint("BOTTOMRIGHT", 0, 0)

	local empty = W.Label(view, "", "GameFontDisable")
	empty:SetPoint("CENTER")
	empty:SetJustifyH("CENTER")

	local function Entries()
		local entries = {}
		local query = search:GetText()
		if query ~= "" then
			for _, contact in ipairs(Contacts.Search(query, 50)) do
				table.insert(entries, { name = Contacts.MailName(contact), contact = contact })
			end
			return entries
		end

		local shown = {}
		local function Add(name, contact, extra)
			local key = Names.Key(name)
			if shown[key] or Names.IsMe(name) then
				return false
			end
			shown[key] = true
			local entry = { name = name, contact = contact }
			for k, v in pairs(extra or {}) do
				entry[k] = v
			end
			table.insert(entries, entry)
			return true
		end

		-- Recent first (up to 6).
		local recentStart = #entries
		table.insert(entries, { header = "Recent" })
		local added = 0
		for _, recent in ipairs(MO.db.recent) do
			if added >= 6 then
				break
			end
			if Add(recent.name, Contacts.FindByName(recent.name), { sentAt = recent.time }) then
				added = added + 1
			end
		end
		if added == 0 then
			table.remove(entries, recentStart + 1)
		end

		-- Then alts, then each contact group. Recent people aren't repeated.
		local sections, order = {}, {}
		for _, contact in ipairs(Contacts.List()) do
			local section = contact.kind == "alt" and "Alts" or (contact.group or "Contacts")
			if not sections[section] then
				sections[section] = {}
				table.insert(order, section)
			end
			table.insert(sections[section], contact)
		end
		for _, section in ipairs(order) do
			local headerIndex = #entries + 1
			table.insert(entries, { header = section })
			local any = false
			for _, contact in ipairs(sections[section]) do
				any = Add(Contacts.MailName(contact), contact) or any
			end
			if not any then
				table.remove(entries, headerIndex)
			end
		end
		return entries
	end

	function view:Refresh()
		RebuildPlan()
		local entries = Entries()
		list:SetData(entries)
		local total = 0
		for _, group in ipairs(plan.groups) do
			total = total + #group.items
		end
		rulesButton:SetText(total > 0 and ("Send by rules (%d)"):format(total) or "Send by rules")
		if #entries == 0 then
			empty:SetText(search:GetText() ~= "" and "Nobody matches." or
				"No one here yet.\nAlts appear after you log in on them;\nadd friends in the Address Book tab.")
		else
			empty:SetText("")
		end
	end

	search:HookScript("OnTextChanged", function()
		view:Refresh()
	end)
	search:HookScript("OnEnterPressed", function()
		-- Enter on a search opens the top match.
		local results = Contacts.Search(search:GetText(), 1)
		if results[1] then
			OpenCompose(Contacts.MailName(results[1]), results[1])
		end
	end)
	view.search = search
end

---------------------------------------------------------------------------
-- Compose view
---------------------------------------------------------------------------
local compose = {} -- state for the open draft

local function BuildComposeView()
	local view = NewView()
	views.compose = view

	local back = W.Button(view.header, "< People", 90, function()
		if Sender.QueueActive() then
			Sender.StopQueue("Stopped.")
		end
		ShowView("people")
	end)
	back:SetPoint("LEFT", 8, 0)

	local queueText = W.Label(view.header, "", "GameFontHighlight")
	queueText:SetPoint("LEFT", back, "RIGHT", 12, 0)

	local skipButton = W.Button(view.header, "Skip", 70, function()
		Sender.SkipQueued()
	end)
	local stopButton = W.Button(view.header, "Stop", 70, function()
		Sender.StopQueue("Stopped.")
		ShowView("people")
	end)
	stopButton:SetPoint("RIGHT", -4, 0)
	skipButton:SetPoint("RIGHT", stopButton, "LEFT", -4, 0)

	-- Recipient
	local recipientIcon = view:CreateTexture(nil, "ARTWORK")
	recipientIcon:SetSize(36, 36)
	recipientIcon:SetPoint("TOPLEFT", 6, -4)
	local toBox = W.EditBox(view, 260, "To")
	toBox:SetPoint("LEFT", recipientIcon, "RIGHT", 14, -6)
	toBox:SetMaxLetters(77)
	local pickButton = W.Button(view, "Address book", 110, function(self)
		W.Menu(self, function(_, root)
			W.AddContactMenu(root, function(contact)
				toBox:SetText(Contacts.MailName(contact))
				compose.contact = contact
				view:RefreshRecipient()
			end)
		end)
	end)
	pickButton:SetPoint("LEFT", toBox, "RIGHT", 8, 0)
	local recipientInfo = W.Label(view, "", "GameFontHighlightSmall")
	recipientInfo:SetPoint("LEFT", pickButton, "RIGHT", 10, 0)
	recipientInfo:SetPoint("RIGHT", -6, 0)
	recipientInfo:SetTextColor(0.7, 0.7, 0.7)

	-- Subject and body
	local subjectBox = W.EditBox(view, 420, "Subject")
	subjectBox:SetPoint("TOPLEFT", recipientIcon, "BOTTOMLEFT", 6, -26)
	subjectBox:SetMaxLetters(64)

	local bodyLabel = W.Label(view, "Message", "GameFontHighlightSmall")
	bodyLabel:SetPoint("TOPLEFT", subjectBox, "BOTTOMLEFT", -4, -10)
	local body = CreateFrame("ScrollFrame", "MailOverhaulComposeBody", view, "InputScrollFrameTemplate")
	body:SetPoint("TOPLEFT", bodyLabel, "BOTTOMLEFT", 4, -8)
	body:SetPoint("RIGHT", view, "RIGHT", -10, 0)
	body:SetHeight(96)
	body.EditBox:SetMaxLetters(500)
	body.EditBox:SetFontObject("ChatFontNormal")
	if body.CharCount then
		body.CharCount:Hide()
	end
	body:SetScript("OnSizeChanged", function(self, width)
		self.EditBox:SetWidth(width - 18)
	end)

	local tabNav = { toBox, subjectBox, body.EditBox }
	for i, box in ipairs(tabNav) do
		box:SetScript("OnTabPressed", function()
			local nextBox = tabNav[(i % #tabNav) + 1]
			nextBox:SetFocus()
		end)
	end

	-- Attachments: 2 rows of 6.
	local attachLabel = W.Label(view, "Attachments  |cff999999(right-click items in your bags)|r", "GameFontHighlightSmall")
	attachLabel:SetPoint("TOPLEFT", body, "BOTTOMLEFT", -4, -14)
	local slots = {}
	for i = 1, Sender.MAX_ATTACHMENTS do
		local slot = W.ItemSlot(view, 40)
		local col, rowIndex = (i - 1) % 6, math.floor((i - 1) / 6)
		slot:SetPoint("TOPLEFT", attachLabel, "BOTTOMLEFT", 4 + col * 44, -6 - rowIndex * 44)
		slot:SetScript("OnClick", function(_, button)
			ClickSendMailItemButton(i, button == "RightButton")
		end)
		slot:SetScript("OnReceiveDrag", function()
			ClickSendMailItemButton(i)
		end)
		slot:SetScript("OnEnter", function(self)
			if GetSendMailItem(i) then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetSendMailItem(i)
				GameTooltip:AddLine("Right-click to remove.", 0.6, 0.8, 1)
				GameTooltip:Show()
			end
		end)
		slots[i] = slot
	end

	-- Money: send gold or COD.
	local moneyLabel = W.Label(view, "Money", "GameFontHighlightSmall")
	moneyLabel:SetPoint("TOPLEFT", attachLabel, "TOPLEFT", 290, 0)
	local sendMoneyCheck = W.Check(view, "Send gold")
	sendMoneyCheck:SetPoint("TOPLEFT", moneyLabel, "BOTTOMLEFT", 0, -4)
	local codCheck = W.Check(view, "Cash on delivery (COD)")
	codCheck:SetPoint("TOPLEFT", sendMoneyCheck, "BOTTOMLEFT", 0, 0)
	sendMoneyCheck:SetScript("OnClick", function()
		sendMoneyCheck:SetChecked(true)
		codCheck:SetChecked(false)
	end)
	codCheck:SetScript("OnClick", function()
		codCheck:SetChecked(true)
		sendMoneyCheck:SetChecked(false)
	end)
	local money = CreateFrame("Frame", "MailOverhaulComposeMoney", view, "MoneyInputFrameTemplate")
	money:SetPoint("TOPLEFT", codCheck, "BOTTOMLEFT", 6, -8)

	-- Items the rules route to this person.
	local ruleStrip = CreateFrame("Frame", nil, view)
	ruleStrip:SetPoint("TOPLEFT", attachLabel, "BOTTOMLEFT", 0, -102)
	ruleStrip:SetPoint("RIGHT", -6, 0)
	ruleStrip:SetHeight(52)
	local ruleBg = ruleStrip:CreateTexture(nil, "BACKGROUND")
	ruleBg:SetAllPoints()
	ruleBg:SetColorTexture(0.25, 0.8, 0.25, 0.08)
	local ruleText = W.Label(ruleStrip, "", "GameFontHighlightSmall")
	ruleText:SetPoint("TOPLEFT", 6, -4)
	local ruleIcons = {}
	for i = 1, Sender.MAX_ATTACHMENTS do
		local icon = CreateFrame("Button", nil, ruleStrip)
		icon:SetSize(24, 24)
		icon:SetPoint("BOTTOMLEFT", 6 + (i - 1) * 27, 4)
		icon.tex = icon:CreateTexture(nil, "ARTWORK")
		icon.tex:SetAllPoints()
		icon:SetScript("OnLeave", GameTooltip_Hide)
		ruleIcons[i] = icon
	end
	local attachRuleButton = W.Button(ruleStrip, "Attach all", 100)
	attachRuleButton:SetPoint("RIGHT", -6, 0)

	-- Footer
	local postage = W.Label(view, "", "GameFontHighlightSmall")
	postage:SetPoint("BOTTOMLEFT", 6, 8)
	local status = W.Label(view, "", "GameFontHighlightSmall")
	status:SetPoint("LEFT", postage, "RIGHT", 16, 0)
	status:SetPoint("RIGHT", -150, 0)
	status:SetTextColor(1, 0.5, 0.5)
	local sendButton = W.Button(view, "Send", 130)
	sendButton:SetPoint("BOTTOMRIGHT", -4, 2)

	function view:RefreshRecipient()
		local name = toBox:GetText()
		local contact = compose.contact
		if not contact or not Names.Equal(Contacts.MailName(contact), name) then
			contact = Contacts.FindByName(name)
			compose.contact = contact
		end
		W.SetClassIcon(recipientIcon, contact and contact.class)
		local info = {}
		if contact then
			table.insert(info, contact.kind == "alt" and "Your alt" or (contact.group or "Contact"))
			if contact.nickname then
				table.insert(info, contact.nickname)
			end
			if not Contacts.SameFaction(contact) then
				table.insert(info, "|cffff5555" .. contact.faction .. "|r")
			end
		elseif name ~= "" then
			table.insert(info, "Not in your address book")
		end
		recipientInfo:SetText(table.concat(info, "  -  "))
		self:RefreshRuleStrip()
	end

	function view:RefreshRuleStrip()
		local group = PlanGroupFor(toBox:GetText())
		local items = group and group.items or {}
		ruleStrip:SetShown(#items > 0 and not Sender.QueueActive())
		ruleText:SetText(("Your rules route |cff40ff40%d item(s)|r to this person:"):format(#items))
		for i, icon in ipairs(ruleIcons) do
			local item = items[i]
			icon:SetShown(item ~= nil)
			if item then
				icon.tex:SetTexture(item.icon)
				icon:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetBagItem(item.bag, item.slot)
					GameTooltip:AddLine("Rule: " .. item.rule.name, 0.6, 0.8, 1)
					GameTooltip:Show()
				end)
			end
		end
		attachRuleButton:SetScript("OnClick", function()
			local attached = Sender.AttachItems(items)
			if attached < #items then
				MO.Print("Attached %d of %d; send this mail, and the rest will still be listed.", attached, #items)
			end
		end)
	end

	function view:RefreshSlots()
		local count = 0
		for i, slot in ipairs(slots) do
			local name, itemID, texture, stackCount, quality = GetSendMailItem(i)
			if name then
				count = count + 1
				W.SetItemSlot(slot, texture, stackCount, quality, itemID)
			else
				W.SetItemSlot(slot, nil, 0, nil, nil)
			end
		end
		postage:SetText("Postage: " .. GetMoneyString(GetSendMailPrice() or 0))
		local isQueued = Sender.QueueActive()
		local sending = Sender.state == "sending"
		sendButton:SetEnabled(not sending and toBox:GetText() ~= "")
		sendButton:SetText(sending and "Sending..." or "Send")
		status:SetText(Sender.message or "")
		queueText:SetText(isQueued and ("Rules mail %d of %d"):format(Sender.index, #Sender.queue) or "")
		skipButton:SetShown(isQueued)
		stopButton:SetShown(isQueued)
		return count
	end

	sendButton:SetScript("OnClick", function()
		local copper = MoneyInputFrame_GetCopper(money) or 0
		Sender.Send({
			recipient = toBox:GetText(),
			subject = subjectBox:GetText(),
			body = body.EditBox:GetText(),
			money = sendMoneyCheck:GetChecked() and copper or 0,
			cod = codCheck:GetChecked() and copper or 0,
		})
	end)

	toBox:HookScript("OnTextChanged", function(_, userInput)
		if userInput then
			compose.contact = nil
			view:RefreshRecipient()
			view:RefreshSlots()
		end
	end)

	-- Clears the draft. keepAttachments leaves the send slots alone (queued mail).
	function view:Reset(name, contact, subject, keepAttachments)
		if not keepAttachments then
			ClearSendMail()
		end
		compose.contact = contact
		toBox:SetText(name or "")
		subjectBox:SetText(subject or "")
		body.EditBox:SetText("")
		MoneyInputFrame_ResetMoney(money)
		sendMoneyCheck:SetChecked(true)
		codCheck:SetChecked(false)
		Sender.message = nil
		self:RefreshRecipient()
		self:RefreshSlots()
		if name and name ~= "" then
			subjectBox:SetFocus()
		else
			toBox:SetFocus()
		end
	end

	function view:Refresh()
		self:RefreshRecipient()
		self:RefreshSlots()
	end

	local events = CreateFrame("Frame", nil, view)
	events:RegisterEvent("MAIL_SEND_INFO_UPDATE")
	events:RegisterEvent("MAIL_SEND_SUCCESS")
	events:SetScript("OnEvent", function()
		if view:IsShown() then
			view:RefreshSlots()
		end
	end)
end

function OpenCompose(name, contact, subject, keepAttachments)
	RebuildPlan()
	ShowView("compose")
	views.compose:Reset(name, contact, subject, keepAttachments)
end

---------------------------------------------------------------------------
-- Plan view ("Send by rules" for everyone)
---------------------------------------------------------------------------
local function BuildPlanView()
	local view = NewView()
	views.plan = view

	local back = W.Button(view.header, "< People", 90, function()
		ShowView("people")
	end)
	back:SetPoint("LEFT", 8, 0)
	local title = W.Label(view.header, "Send by rules", "GameFontHighlight")
	title:SetPoint("LEFT", back, "RIGHT", 12, 0)
	local editRules = W.Button(view.header, "Edit rules", 100, function()
		MO.Mailbox.SelectTab("rules")
	end)
	editRules:SetPoint("RIGHT", -4, 0)

	local status, startButton

	local function CountSelected()
		local count, mails = 0, 0
		for _, group in ipairs(plan and plan.groups or {}) do
			local n = 0
			for _, item in ipairs(group.items) do
				if item.selected then
					n = n + 1
				end
			end
			count = count + n
			mails = mails + math.ceil(n / Sender.MAX_ATTACHMENTS)
		end
		return count, mails
	end

	local function UpdateFooter()
		local count, mails = CountSelected()
		startButton:SetText(count > 0 and ("Start: %d item(s) in %d mail(s)"):format(count, mails) or "Nothing to send")
		startButton:SetEnabled(count > 0)
		local notes = {}
		if plan.pending > 0 then
			table.insert(notes, ("%d item(s) still loading..."):format(plan.pending))
		end
		if plan.skippedSelf > 0 then
			table.insert(notes, ("%d item(s) skipped because their rule sends to you."):format(plan.skippedSelf))
		end
		if plan.noRecipient > 0 then
			table.insert(notes, ("|cffff5555%d item(s) match a rule with no recipient.|r"):format(plan.noRecipient))
		end
		if #plan.groups == 0 then
			table.insert(notes, #Rules.List() == 0 and "No rules yet. Click 'Edit rules' to make one." or
				"Nothing in your bags matches your rules.")
		end
		status:SetText(table.concat(notes, "\n"))
	end

	local function Build(row)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.check:SetSize(22, 22)
		row.check:SetPoint("LEFT", 4, 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(18, 18)
		row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
		row.text = W.Label(row, "", "GameFontHighlightSmall")
		row.text:SetWordWrap(false)
		row:SetScript("OnLeave", GameTooltip_Hide)
	end

	local function Update(row, data)
		row.text:ClearAllPoints()
		if data.group then
			local group = data.group
			row.check:Hide()
			row.icon:Hide()
			row.text:SetPoint("LEFT", 4, -4)
			row.text:SetPoint("RIGHT", -4, 0)
			local contact = group.contact
			row.text:SetText("|cffffd100To:|r " .. Names.ClassColored(group.recipient, contact and contact.class))
			row:SetScript("OnEnter", nil)
			row:SetScript("OnClick", nil)
			return
		end
		local item = data.item
		row.check:Show()
		row.icon:Show()
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.text:SetPoint("RIGHT", -4, 0)
		row.check:SetChecked(item.selected)
		row.check:SetScript("OnClick", function(self)
			item.selected = self:GetChecked()
			UpdateFooter()
		end)
		row.icon:SetTexture(item.icon)
		local countText = (item.count or 1) > 1 and (" x" .. item.count) or ""
		row.text:SetText(item.link .. countText .. "  |cff777777" .. item.rule.name .. "|r")
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetBagItem(item.bag, item.slot)
			GameTooltip:AddLine("Rule: " .. item.rule.name, 0.6, 0.8, 1)
			GameTooltip:Show()
		end)
		row:SetScript("OnClick", function()
			item.selected = not item.selected
			row.check:SetChecked(item.selected)
			UpdateFooter()
		end)
	end

	local list = W.List(view, function(data)
		return data.group and 26 or 22
	end, Build, Update)
	list:SetPoint("TOPLEFT", 0, 0)
	list:SetPoint("BOTTOMRIGHT", 0, 64)

	status = W.Label(view, "", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", 6, 34)
	status:SetPoint("RIGHT", -6, 0)
	status:SetWordWrap(true)

	startButton = W.Button(view, "", 260, function()
		Sender.StartQueue(plan)
	end)
	startButton:SetPoint("BOTTOMRIGHT", -4, 2)

	function view:Refresh()
		RebuildPlan()
		local rows = {}
		for _, group in ipairs(plan.groups) do
			table.insert(rows, { group = group })
			for _, item in ipairs(group.items) do
				table.insert(rows, { item = item })
			end
		end
		list:SetData(rows)
		UpdateFooter()
	end
end

---------------------------------------------------------------------------

function SendTab.Build(tabPage)
	page = tabPage
	BuildPeopleView()
	BuildComposeView()
	BuildPlanView()

	function page:Refresh()
		if currentView == "compose" or Sender.QueueActive() then
			ShowView("compose")
		else
			ShowView(currentView)
		end
	end
	page:SetScript("OnHide", function()
		SetSendMailShowing(false)
	end)

	-- Queue: show each staged mail in compose.
	MO.On("QUEUE_STAGED", function(mail)
		if MO.Mailbox.CurrentTab() ~= "send" then
			MO.Mailbox.SelectTab("send")
		end
		OpenCompose(mail.recipient, mail.contact, mail.subject, true)
	end)
	MO.On("MAIL_SENT", function(_, fromQueue)
		if fromQueue then
			return -- the next mail (or the end of the queue) updates the view
		end
		if currentView == "compose" then
			ShowView("people")
		end
	end)
	MO.On("SENDER_CHANGED", function()
		if not page:IsVisible() then
			return
		end
		if currentView == "compose" then
			views.compose:RefreshSlots()
			-- Queue just finished: back to people.
			if not Sender.QueueActive() and Sender.message == "All rule mail sent." then
				MO.Print(Sender.message)
				Sender.message = nil
				ShowView("people")
			end
		end
	end)

	-- Keep counts current while browsing people or the plan.
	local pending = false
	local events = CreateFrame("Frame", nil, page)
	events:RegisterEvent("BAG_UPDATE_DELAYED")
	events:SetScript("OnEvent", function()
		if pending or not page:IsVisible() or Sender.QueueActive() then
			return
		end
		pending = true
		C_Timer.After(0.3, function()
			pending = false
			if currentView == "compose" then
				RebuildPlan()
				views.compose:RefreshRuleStrip()
			elseif views[currentView]:IsVisible() then
				views[currentView]:Refresh()
			end
		end)
	end)
	MO.On("RULES_CHANGED", function()
		if page:IsVisible() and currentView ~= "compose" then
			views[currentView]:Refresh()
		end
	end)
end

function SendTab.ComposeTo(name, subject)
	MO.Mailbox.SelectTab("send")
	OpenCompose(name, Contacts.FindByName(name), subject)
end
