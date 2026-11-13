local _, ns = ...
local MO = ns.Modules.MailOverhaul

-- Small builders around Blizzard templates, styled like Forever's newer windows.
local W = {}
MO.Widgets = W

function W.Label(parent, text, template)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
	fs:SetText(text or "")
	fs:SetJustifyH("LEFT")
	return fs
end

function W.Button(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 100, 22)
	button:SetText(text)
	if onClick then
		button:SetScript("OnClick", onClick)
	end
	return button
end

function W.EditBox(parent, width, label)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width or 160, 20)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	if label then
		box.label = W.Label(parent, label, "GameFontHighlightSmall")
		box.label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", -4, 2)
	end
	return box
end

function W.SearchBox(parent, width, instructions)
	local box = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
	box:SetSize(width or 200, 20)
	if instructions and box.Instructions then
		box.Instructions:SetText(instructions)
	end
	return box
end

function W.Check(parent, text, onClick)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check.label = W.Label(parent, text, "GameFontHighlightSmall")
	check.label:SetPoint("LEFT", check, "RIGHT", 2, 1)
	if onClick then
		check:SetScript("OnClick", onClick)
	end
	return check
end

-- Adds highlight, selection and a text label to a list row button.
function W.StyleRow(row)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints()
	row.selected:SetColorTexture(1, 0.82, 0, 0.15)
	row.selected:Hide()
	row.text = W.Label(row, "", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 4, 0)
	row.text:SetPoint("RIGHT", -4, 0)
	row.text:SetWordWrap(false)
end

--[[ A scrolling list built on Blizzard's ScrollBox (the modern list used by Forever's UI).
	build(row)               one-time setup of a pooled row Button
	update(row, data, index) fills a row; rows are reused, so set every field
	extent                   row height, or function(data) -> height
Returns a container frame with :SetData(array). ]]
function W.List(parent, extent, build, update)
	local container = CreateFrame("Frame", nil, parent)
	local scrollBox = CreateFrame("Frame", nil, container, "WowScrollBoxList")
	local scrollBar = CreateFrame("EventFrame", nil, container, "MinimalScrollBar")
	scrollBox:SetPoint("TOPLEFT")
	scrollBox:SetPoint("BOTTOMRIGHT", -16, 0)
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

	local view = CreateScrollBoxListLinearView()
	if type(extent) == "function" then
		view:SetElementExtentCalculator(function(_, entry)
			return extent(entry.data)
		end)
	else
		view:SetElementExtent(extent)
	end
	view:SetElementInitializer("Button", function(row, entry)
		if not row.mrBuilt then
			row.mrBuilt = true
			build(row)
		end
		update(row, entry.data, entry.index)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	container.scrollBox = scrollBox

	function container:SetData(array)
		local entries = {}
		for i, data in ipairs(array) do
			entries[i] = { data = data, index = i }
		end
		scrollBox:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition)
	end

	-- Re-run update() on visible rows without rebuilding the data.
	function container:RefreshRows()
		scrollBox:ForEachFrame(function(row, entry)
			update(row, entry.data, entry.index)
		end)
	end

	return container
end

-- An item slot button (mail attachments).
function W.ItemSlot(parent, size)
	local button = CreateFrame("ItemButton", nil, parent)
	button:SetSize(size or 37, size or 37)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

function W.SetItemSlot(button, texture, count, quality, itemIDOrLink)
	SetItemButtonTexture(button, texture)
	SetItemButtonCount(button, count or 0)
	if button.SetItemButtonQuality then
		button:SetItemButtonQuality(quality, itemIDOrLink)
	end
end

function W.SetClassIcon(texture, classFile)
	if classFile and C_Texture.GetAtlasInfo(GetClassAtlas(classFile)) then
		texture:SetAtlas(GetClassAtlas(classFile))
	elseif classFile and CLASS_ICON_TCOORDS[classFile] then
		texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		texture:SetTexCoord(unpack(CLASS_ICON_TCOORDS[classFile]))
	else
		texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

-- Opens a context menu built by generator(owner, rootDescription).
function W.Menu(owner, generator)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, generator)
	else
		MO.Print("Menus aren't available in this client.")
	end
end

-- Adds a "pick a contact" tree to a menu; onPick(contact).
function W.AddContactMenu(root, onPick)
	local list = MO.Contacts.List()
	if #list == 0 then
		root:CreateTitle("Address book is empty")
		return
	end
	local alts, groups, groupOrder = {}, {}, {}
	for _, contact in ipairs(list) do
		if contact.kind == "alt" then
			table.insert(alts, contact)
		else
			local group = contact.group or "Contacts"
			if not groups[group] then
				groups[group] = {}
				table.insert(groupOrder, group)
			end
			table.insert(groups[group], contact)
		end
	end
	local function AddEntry(parentDesc, contact)
		local text = MO.Names.ClassColored(MO.Contacts.DisplayName(contact), contact.class)
		if MO.Contacts.IsMe(contact) then
			text = text .. " |cff888888(you)|r"
		end
		parentDesc:CreateButton(text, function()
			onPick(contact)
		end)
	end
	if #alts > 0 then
		root:CreateTitle("Alts")
		for _, contact in ipairs(alts) do
			AddEntry(root, contact)
		end
	end
	for _, group in ipairs(groupOrder) do
		root:CreateTitle(group)
		for _, contact in ipairs(groups[group]) do
			AddEntry(root, contact)
		end
	end
end

-- Short "3d ago" style text for a time() value.
function W.Ago(timestamp)
	if not timestamp then
		return nil
	end
	local seconds = time() - timestamp
	if seconds < 3600 then
		return "just now"
	elseif seconds < 86400 then
		return ("%dh ago"):format(seconds / 3600)
	end
	return ("%dd ago"):format(seconds / 86400)
end
