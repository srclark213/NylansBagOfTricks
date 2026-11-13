local _, ns = ...
local MO = ns.Modules.MailOverhaul

local RulesTab = {}
MO.RulesTab = RulesTab

local W = MO.Widgets
local Rules = MO.Rules
local Contacts = MO.Contacts
local Names = MO.Names

-- The edit box that should receive shift-clicked item links, if any.
local linkTarget

local function HookItemLinks()
	local function Insert(link)
		if linkTarget and linkTarget:IsVisible() and linkTarget:HasFocus() and link then
			linkTarget:Insert(link)
		end
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", Insert)
	elseif ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", Insert)
	end
end

local function RecipientText(rule)
	local name, contact = Rules.Recipient(rule)
	if not name then
		return "|cffff5555(no recipient)|r"
	end
	return Names.ClassColored(name, contact and contact.class)
end

function RulesTab.Build(panel)
	HookItemLinks()
	local selectedId
	local draft -- working copy of the selected rule's editable fields

	-- Left: ordered rule list.
	local list
	list = W.List(panel, 20, function(row)
		W.StyleRow(row)
		row.text:SetPoint("RIGHT", -44, 0)
		row.up = CreateFrame("Button", nil, row)
		row.up:SetSize(18, 18)
		row.up:SetPoint("RIGHT", -20, 0)
		row.up:SetNormalTexture("Interface\\Buttons\\Arrow-Up-Up")
		row.up:SetPushedTexture("Interface\\Buttons\\Arrow-Up-Down")
		row.down = CreateFrame("Button", nil, row)
		row.down:SetSize(18, 18)
		row.down:SetPoint("RIGHT", -2, 0)
		row.down:SetNormalTexture("Interface\\Buttons\\Arrow-Down-Up")
		row.down:SetPushedTexture("Interface\\Buttons\\Arrow-Down-Down")
	end, function(row, rule, index)
		local text = ("%d. %s |cff999999-> |r%s"):format(index, rule.name, RecipientText(rule))
		if not rule.enabled then
			text = "|cff777777" .. ("%d. %s (off)"):format(index, rule.name) .. "|r"
		end
		row.text:SetText(text)
		row.selected:SetShown(rule.id == selectedId)
		row:SetScript("OnClick", function()
			selectedId = rule.id
			panel:Refresh()
		end)
		row.up:SetScript("OnClick", function()
			Rules.Move(rule.id, -1)
		end)
		row.down:SetScript("OnClick", function()
			Rules.Move(rule.id, 1)
		end)
	end)
	list:SetPoint("TOPLEFT", 0, 0)
	list:SetPoint("BOTTOMLEFT", 0, 34)
	list:SetWidth(240)

	local orderHint = W.Label(panel, "Rules are checked top to bottom; the first match wins.", "GameFontDisableSmall")
	orderHint:SetPoint("BOTTOMLEFT", 0, 26)

	-- Right: editor.
	local editor = CreateFrame("Frame", nil, panel)
	editor:SetPoint("TOPLEFT", list, "TOPRIGHT", 30, 0)
	editor:SetPoint("BOTTOMRIGHT", 0, 34)

	local nameBox = W.EditBox(editor, 200, "Rule name")
	nameBox:SetPoint("TOPLEFT", 6, -14)

	local enabledCheck = W.Check(editor, "Enabled")
	enabledCheck:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)

	-- Recipient: pick from address book or type a name.
	local recipientLabel = W.Label(editor, "Send to", "GameFontHighlightSmall")
	recipientLabel:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -10)

	local recipientBox = W.EditBox(editor, 200)
	recipientBox:SetPoint("TOPLEFT", recipientLabel, "BOTTOMLEFT", 6, -4)
	recipientBox:SetMaxLetters(77)
	recipientBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput and draft then
			draft.contactId = nil
			draft.recipientName = self:GetText()
		end
	end)

	local pickButton = W.Button(editor, "Address book", 110, function(self)
		W.Menu(self, function(_, root)
			W.AddContactMenu(root, function(contact)
				if draft then
					draft.contactId = contact.id
					draft.recipientName = nil
					recipientBox:SetText(Contacts.MailName(contact))
				end
			end)
		end)
	end)
	pickButton:SetPoint("LEFT", recipientBox, "RIGHT", 6, 0)

	-- Quality range.
	local qualityLabel = W.Label(editor, "Quality", "GameFontHighlightSmall")
	qualityLabel:SetPoint("TOPLEFT", recipientBox, "BOTTOMLEFT", -6, -10)

	local function QualityButton(field)
		local button = W.Button(editor, "", 100)
		button:SetScript("OnClick", function(self)
			W.Menu(self, function(_, root)
				for q = 0, Rules.MAX_QUALITY do
					root:CreateButton(Rules.QualityColored(q), function()
						draft[field] = q
						if draft.minQuality > draft.maxQuality then
							if field == "minQuality" then
								draft.maxQuality = q
							else
								draft.minQuality = q
							end
						end
						panel:RefreshEditor()
					end)
				end
			end)
		end)
		return button
	end
	local minQualityButton = QualityButton("minQuality")
	minQualityButton:SetPoint("TOPLEFT", qualityLabel, "BOTTOMLEFT", 0, -4)
	local toLabel = W.Label(editor, "to", "GameFontHighlightSmall")
	toLabel:SetPoint("LEFT", minQualityButton, "RIGHT", 6, 0)
	local maxQualityButton = QualityButton("maxQuality")
	maxQualityButton:SetPoint("LEFT", toLabel, "RIGHT", 6, 0)

	-- Item categories.
	local categoryLabel = W.Label(editor, "Item types (none checked = any)", "GameFontHighlightSmall")
	categoryLabel:SetPoint("TOPLEFT", minQualityButton, "BOTTOMLEFT", 0, -10)
	local categoryChecks = {}
	for i, classID in ipairs(Rules.CATEGORY_ORDER) do
		local check = W.Check(editor, Rules.ClassName(classID), function(self)
			draft.classes[classID] = self:GetChecked() or nil
		end)
		local col, rowIndex = (i - 1) % 3, math.floor((i - 1) / 3)
		check:SetPoint("TOPLEFT", categoryLabel, "BOTTOMLEFT", col * 115, -2 - rowIndex * 22)
		categoryChecks[classID] = check
	end

	local disenchantCheck = W.Check(editor, "Only disenchantable (green-epic armor and weapons)", function(self)
		draft.disenchantable = self:GetChecked()
	end)
	disenchantCheck:SetPoint("TOPLEFT", categoryLabel, "BOTTOMLEFT", 0, -96)

	local minIlvlBox = W.EditBox(editor, 50, "Min item level")
	minIlvlBox:SetPoint("TOPLEFT", disenchantCheck, "BOTTOMLEFT", 6, -18)
	minIlvlBox:SetNumeric(true)
	local maxIlvlBox = W.EditBox(editor, 50, "Max item level")
	maxIlvlBox:SetPoint("LEFT", minIlvlBox, "RIGHT", 60, 0)
	maxIlvlBox:SetNumeric(true)

	local nameContainsBox = W.EditBox(editor, 120, "Name contains")
	nameContainsBox:SetPoint("LEFT", maxIlvlBox, "RIGHT", 60, 0)

	local itemIDsBox = W.EditBox(editor, 320, "Only these items (IDs, or shift-click items in)")
	itemIDsBox:SetPoint("TOPLEFT", minIlvlBox, "BOTTOMLEFT", 0, -22)
	itemIDsBox:SetMaxLetters(0)
	itemIDsBox:SetScript("OnEditFocusGained", function(self)
		linkTarget = self
	end)

	local saveButton = W.Button(editor, "Save", 90)
	saveButton:SetPoint("TOPLEFT", itemIDsBox, "BOTTOMLEFT", -6, -12)
	local deleteButton = W.Button(editor, "Delete", 90)
	deleteButton:SetPoint("LEFT", saveButton, "RIGHT", 6, 0)

	local emptyText = W.Label(editor, "Select a rule, or create one below.", "GameFontDisable")
	emptyText:SetPoint("CENTER")

	local editorWidgets = {
		nameBox, enabledCheck, recipientLabel, recipientBox, pickButton, qualityLabel, minQualityButton,
		toLabel, maxQualityButton, categoryLabel, disenchantCheck, minIlvlBox, maxIlvlBox, nameContainsBox,
		itemIDsBox, saveButton, deleteButton,
	}
	for _, check in pairs(categoryChecks) do
		table.insert(editorWidgets, check)
		table.insert(editorWidgets, check.label)
	end
	for _, widget in ipairs({ enabledCheck, disenchantCheck }) do
		table.insert(editorWidgets, widget.label)
	end
	for _, box in ipairs({ nameBox, minIlvlBox, maxIlvlBox, nameContainsBox, itemIDsBox }) do
		table.insert(editorWidgets, box.label)
	end

	local function SetEditorShown(shown)
		for _, widget in ipairs(editorWidgets) do
			widget:SetShown(shown)
		end
		emptyText:SetShown(not shown)
	end

	local function LoadDraft(rule)
		draft = {
			contactId = rule.contactId,
			recipientName = rule.recipientName,
			minQuality = rule.minQuality or 0,
			maxQuality = rule.maxQuality or Rules.MAX_QUALITY,
			classes = CopyTable(rule.classes or {}),
			disenchantable = rule.disenchantable,
		}
	end

	function panel:RefreshEditor()
		local rule = Rules.Get(selectedId)
		SetEditorShown(rule ~= nil)
		if not rule then
			return
		end
		minQualityButton:SetText(Rules.QualityColored(draft.minQuality))
		maxQualityButton:SetText(Rules.QualityColored(draft.maxQuality))
		for classID, check in pairs(categoryChecks) do
			check:SetChecked(draft.classes[classID] == true)
		end
		disenchantCheck:SetChecked(draft.disenchantable)
	end

	local function LoadRule(rule)
		LoadDraft(rule)
		nameBox:SetText(rule.name or "")
		enabledCheck:SetChecked(rule.enabled)
		recipientBox:SetText(Rules.Recipient(rule) or "")
		minIlvlBox:SetText(rule.minIlvl and tostring(rule.minIlvl) or "")
		maxIlvlBox:SetText(rule.maxIlvl and tostring(rule.maxIlvl) or "")
		nameContainsBox:SetText(rule.nameContains or "")
		itemIDsBox:SetText(Rules.FormatItemIDs(rule.itemIDs))
	end

	saveButton:SetScript("OnClick", function()
		local rule = Rules.Get(selectedId)
		if not rule then
			return
		end
		rule.name = Names.Clean(nameBox:GetText())
		if rule.name == "" then
			rule.name = "Rule " .. rule.id
		end
		rule.enabled = enabledCheck:GetChecked()
		rule.contactId = draft.contactId
		rule.recipientName = not draft.contactId and Names.Clean(recipientBox:GetText()) or nil
		rule.minQuality = draft.minQuality
		rule.maxQuality = draft.maxQuality
		rule.classes = draft.classes
		rule.disenchantable = draft.disenchantable and true or false
		rule.minIlvl = tonumber(minIlvlBox:GetText())
		rule.maxIlvl = tonumber(maxIlvlBox:GetText())
		local contains = Names.Clean(nameContainsBox:GetText())
		rule.nameContains = contains ~= "" and contains or nil
		rule.itemIDs = Rules.ParseItemIDs(itemIDsBox:GetText())
		Rules.Save(rule)
		LoadRule(rule)
		MO.Print("Saved rule '%s'.", rule.name)
	end)

	deleteButton:SetScript("OnClick", function()
		if selectedId then
			Rules.Delete(selectedId)
			selectedId = nil
		end
	end)

	-- Bottom bar.
	local function NewRule(preset)
		local rule = Rules.New(preset)
		selectedId = rule.id
		LoadRule(rule)
		panel:Refresh()
	end
	local newButton = W.Button(panel, "New rule", 100, function()
		NewRule()
	end)
	newButton:SetPoint("BOTTOMLEFT", 0, 0)
	local deButton = W.Button(panel, "New disenchant rule", 150, function()
		NewRule("disenchant")
	end)
	deButton:SetPoint("LEFT", newButton, "RIGHT", 6, 0)

	local loadedId
	function panel:Refresh()
		list:SetData(Rules.List())
		local rule = Rules.Get(selectedId)
		if not rule then
			selectedId = nil
			loadedId = nil
		elseif loadedId ~= selectedId then
			loadedId = selectedId
			LoadRule(rule)
		end
		self:RefreshEditor()
	end

	MO.On("RULES_CHANGED", function()
		if panel:IsVisible() then
			panel:Refresh()
		end
	end)
	MO.On("CONTACTS_CHANGED", function()
		if panel:IsVisible() then
			list:SetData(Rules.List())
		end
	end)
end
