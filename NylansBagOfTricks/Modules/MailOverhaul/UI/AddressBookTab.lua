local _, ns = ...
local MO = ns.Modules.MailOverhaul

local AddressBookTab = {}
MO.AddressBookTab = AddressBookTab

local W = MO.Widgets
local Contacts = MO.Contacts
local Names = MO.Names

function AddressBookTab.Build(panel)
	local selectedId

	-- Left: list of contacts.
	local list
	list = W.List(panel, 20, W.StyleRow, function(row, contact)
		local text = Names.ClassColored(Contacts.MailName(contact), contact.class)
		local extra = {}
		if contact.nickname then
			table.insert(extra, contact.nickname)
		end
		if contact.kind == "alt" then
			table.insert(extra, contact.level and ("alt, " .. contact.level) or "alt")
		elseif contact.group then
			table.insert(extra, contact.group)
		end
		if #extra > 0 then
			text = text .. " |cff999999" .. table.concat(extra, " - ") .. "|r"
		end
		row.text:SetText(text)
		row.selected:SetShown(contact.id == selectedId)
		row:SetScript("OnClick", function()
			selectedId = contact.id
			panel:Refresh()
		end)
	end)
	list:SetPoint("TOPLEFT", 0, 0)
	list:SetPoint("BOTTOMLEFT", 0, 34)
	list:SetWidth(280)

	-- Right: editor.
	local editor = CreateFrame("Frame", nil, panel)
	editor:SetPoint("TOPLEFT", list, "TOPRIGHT", 30, 0)
	editor:SetPoint("BOTTOMRIGHT", 0, 34)

	local heading = W.Label(editor, "", "GameFontNormalLarge")
	heading:SetPoint("TOPLEFT", 0, 0)
	heading:SetPoint("RIGHT", 0, 0)

	local info = W.Label(editor, "", "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
	info:SetPoint("RIGHT", 0, 0)

	local nameBox = W.EditBox(editor, 250, "Mail name (exactly what goes in To:)")
	nameBox:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 6, -26)
	nameBox:SetMaxLetters(77)

	local nickBox = W.EditBox(editor, 250, "Nickname")
	nickBox:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -24)

	local groupBox = W.EditBox(editor, 250, "Group")
	groupBox:SetPoint("TOPLEFT", nickBox, "BOTTOMLEFT", 0, -24)

	local noteBox = W.EditBox(editor, 250, "Note")
	noteBox:SetPoint("TOPLEFT", groupBox, "BOTTOMLEFT", 0, -24)

	local hint = W.Label(editor, "", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", noteBox, "BOTTOMLEFT", -6, -10)
	hint:SetPoint("RIGHT", 0, 0)
	hint:SetWordWrap(true)

	local saveButton = W.Button(editor, "Save", 90)
	saveButton:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)

	local deleteButton = W.Button(editor, "Delete", 90)
	deleteButton:SetPoint("LEFT", saveButton, "RIGHT", 6, 0)

	local function Save()
		local fields = {
			name = nameBox:GetText(),
			nickname = nickBox:GetText(),
			group = groupBox:GetText(),
			note = noteBox:GetText(),
		}
		if selectedId then
			Contacts.Update(selectedId, fields)
		else
			local contact, err = Contacts.Add(fields)
			if err then
				MO.Print(err)
			end
			selectedId = contact and contact.id
		end
		panel:Refresh()
	end
	saveButton:SetScript("OnClick", Save)
	for _, box in ipairs({ nameBox, nickBox, groupBox, noteBox }) do
		box:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
			Save()
		end)
	end

	deleteButton:SetScript("OnClick", function()
		if selectedId then
			Contacts.Delete(selectedId)
			selectedId = nil
			panel:Refresh()
		end
	end)

	-- Bottom bar.
	local newButton = W.Button(panel, "New contact", 110, function()
		selectedId = nil
		panel:Refresh()
		nameBox:SetFocus()
	end)
	newButton:SetPoint("BOTTOMLEFT", 0, 0)

	local targetButton = W.Button(panel, "Add target", 110, function()
		local contact, err = Contacts.AddTarget()
		if err then
			MO.Print(err)
		end
		if contact then
			selectedId = contact.id
		end
		panel:Refresh()
	end)
	targetButton:SetPoint("LEFT", newButton, "RIGHT", 6, 0)

	local friendsButton = W.Button(panel, "Import friends", 120, function()
		MO.Print("Added %d friend(s).", Contacts.ImportFriends())
		panel:Refresh()
	end)
	friendsButton:SetPoint("LEFT", targetButton, "RIGHT", 6, 0)

	local whoami = W.Label(panel, "", "GameFontDisableSmall")
	whoami:SetPoint("BOTTOMRIGHT", 0, 6)

	function panel:Refresh()
		local contacts = Contacts.List()
		local contact = Contacts.Get(selectedId)
		if not contact then
			selectedId = nil
		end
		list:SetData(contacts)

		if contact then
			heading:SetText(Names.ClassColored(Contacts.MailName(contact), contact.class))
			local parts = { contact.kind == "alt" and "Alt" or "Contact" }
			if contact.level then
				table.insert(parts, "level " .. contact.level)
			end
			if contact.faction then
				table.insert(parts, contact.faction)
			end
			if contact.realm then
				table.insert(parts, contact.realm)
			end
			info:SetText(table.concat(parts, " - "))
			nameBox:SetText(Contacts.MailName(contact))
			if contact.kind == "alt" then
				hint:SetText(("Detected on login as '%s'. Change the mail name only if mail to the detected name fails."):format(contact.name))
			else
				hint:SetText("")
			end
			deleteButton:Enable()
		else
			heading:SetText("New contact")
			info:SetText("Your alts are added automatically when you log in on them.")
			nameBox:SetText("")
			hint:SetText("Use the full 'First Last' name.")
			deleteButton:Disable()
		end
		nickBox:SetText(contact and contact.nickname or "")
		groupBox:SetText(contact and contact.group or "")
		noteBox:SetText(contact and contact.note or "")
		whoami:SetText("You: " .. (Names.GetPlayerFullName() or "?"))
	end

	MO.On("CONTACTS_CHANGED", function()
		if panel:IsVisible() then
			panel:Refresh()
		end
	end)
end
