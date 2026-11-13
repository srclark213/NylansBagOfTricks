local _, ns = ...
local MO = ns.Modules.MailOverhaul

--[[ Rules: the first enabled rule that matches an item decides its recipient.

rule = {
	id             = number,
	name           = string,
	enabled        = bool,
	contactId      = string?,  -- address book entry
	recipientName  = string?,  -- typed name, used when contactId is nil
	minQuality     = number,   -- Enum.ItemQuality
	maxQuality     = number,
	classes        = { [classID] = true }, -- empty = any item class
	disenchantable = bool,
	minIlvl        = number?,
	maxIlvl        = number?,
	itemIDs        = { [itemID] = true },  -- empty = any item
	nameContains   = string?,
}
]]
local Rules = {}
MO.Rules = Rules

local Names = MO.Names

local ITEM_CLASS = {
	CONSUMABLE = 0, CONTAINER = 1, WEAPON = 2, GEM = 3, ARMOR = 4, REAGENT = 5,
	PROJECTILE = 6, TRADEGOODS = 7, RECIPE = 9, QUIVER = 11, QUEST = 12, KEY = 13, MISC = 15,
}
Rules.ITEM_CLASS = ITEM_CLASS

-- Item classes offered in the rule editor, in display order.
Rules.CATEGORY_ORDER = {
	ITEM_CLASS.WEAPON, ITEM_CLASS.ARMOR, ITEM_CLASS.CONSUMABLE, ITEM_CLASS.TRADEGOODS,
	ITEM_CLASS.RECIPE, ITEM_CLASS.REAGENT, ITEM_CLASS.CONTAINER, ITEM_CLASS.GEM,
	ITEM_CLASS.PROJECTILE, ITEM_CLASS.QUIVER, ITEM_CLASS.MISC,
}

local FALLBACK_CLASS_NAMES = {
	[0] = "Consumable", [1] = "Container", [2] = "Weapon", [3] = "Gem", [4] = "Armor", [5] = "Reagent",
	[6] = "Projectile", [7] = "Trade Goods", [9] = "Recipe", [11] = "Quiver", [12] = "Quest", [13] = "Key", [15] = "Miscellaneous",
}

function Rules.ClassName(classID)
	local getter = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
	local name = getter and getter(classID)
	return (name and name ~= "") and name or FALLBACK_CLASS_NAMES[classID] or ("Class " .. classID)
end

Rules.MAX_QUALITY = 7

function Rules.QualityName(quality)
	return _G["ITEM_QUALITY" .. quality .. "_DESC"] or ("Quality " .. quality)
end

function Rules.QualityColored(quality, text)
	text = text or Rules.QualityName(quality)
	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color and color.hex then
		return color.hex .. text .. "|r"
	end
	return text
end

-- Equip slots that are armor-class but can never be disenchanted.
local NOT_DISENCHANTABLE_SLOTS = { INVTYPE_BODY = true, INVTYPE_TABARD = true, [""] = true }

function Rules.IsDisenchantable(item)
	if item.classID ~= ITEM_CLASS.WEAPON and item.classID ~= ITEM_CLASS.ARMOR then
		return false
	end
	if item.quality < 2 or item.quality > 4 then
		return false
	end
	return not NOT_DISENCHANTABLE_SLOTS[item.equipLoc or ""]
end

local function DB()
	return MO.db.rules
end

function Rules.List()
	return DB()
end

function Rules.Get(id)
	for index, rule in ipairs(DB()) do
		if rule.id == id then
			return rule, index
		end
	end
	return nil
end

local function NextId()
	local maxId = 0
	for _, rule in ipairs(DB()) do
		maxId = math.max(maxId, rule.id or 0)
	end
	return maxId + 1
end

function Rules.New(preset)
	local rule = {
		id = NextId(),
		name = "New rule",
		enabled = true,
		minQuality = 0,
		maxQuality = Rules.MAX_QUALITY,
		classes = {},
		disenchantable = false,
		itemIDs = {},
	}
	if preset == "disenchant" then
		rule.name = "Disenchant greens"
		rule.minQuality = 2
		rule.maxQuality = 2
		rule.classes = { [ITEM_CLASS.WEAPON] = true, [ITEM_CLASS.ARMOR] = true }
		rule.disenchantable = true
	end
	table.insert(DB(), rule)
	MO.Fire("RULES_CHANGED")
	return rule
end

function Rules.Save(rule)
	MO.Fire("RULES_CHANGED")
	return rule
end

function Rules.Delete(id)
	local _, index = Rules.Get(id)
	if index then
		table.remove(DB(), index)
		MO.Fire("RULES_CHANGED")
	end
end

function Rules.Move(id, delta)
	local _, index = Rules.Get(id)
	local target = index and index + delta
	if not target or target < 1 or target > #DB() then
		return
	end
	local list = DB()
	list[index], list[target] = list[target], list[index]
	MO.Fire("RULES_CHANGED")
end

-- Returns mailName, contact (contact may be nil for a typed name).
function Rules.Recipient(rule)
	local contact = MO.Contacts.Get(rule.contactId)
	if contact then
		return MO.Contacts.MailName(contact), contact
	end
	if rule.recipientName and rule.recipientName ~= "" then
		return rule.recipientName, MO.Contacts.FindByName(rule.recipientName)
	end
	return nil
end

-- Parses "123, 456, |Hitem:789:...|h" into a set of item IDs.
function Rules.ParseItemIDs(text)
	local ids = {}
	for id in (text or ""):gmatch("item:(%d+)") do
		ids[tonumber(id)] = true
	end
	local stripped = (text or ""):gsub("|c%x+|Hitem:[^|]+|h[^|]*|h|r", ""):gsub("|Hitem:[^|]+|h[^|]*|h", "")
	for id in stripped:gmatch("%d+") do
		ids[tonumber(id)] = true
	end
	return ids
end

function Rules.FormatItemIDs(ids)
	local list = {}
	for id in pairs(ids or {}) do
		table.insert(list, id)
	end
	table.sort(list)
	return table.concat(list, ", ")
end

function Rules.Matches(rule, item)
	if not rule.enabled then
		return false
	end
	if item.quality < (rule.minQuality or 0) or item.quality > (rule.maxQuality or Rules.MAX_QUALITY) then
		return false
	end
	if next(rule.classes or {}) and not rule.classes[item.classID] then
		return false
	end
	if rule.disenchantable and not Rules.IsDisenchantable(item) then
		return false
	end
	if rule.minIlvl and item.ilvl < rule.minIlvl then
		return false
	end
	if rule.maxIlvl and item.ilvl > rule.maxIlvl then
		return false
	end
	if next(rule.itemIDs or {}) and not rule.itemIDs[item.itemID] then
		return false
	end
	if rule.nameContains and rule.nameContains ~= "" then
		if not strlower(item.name):find(strlower(rule.nameContains), 1, true) then
			return false
		end
	end
	return true
end

function Rules.FirstMatch(item)
	for _, rule in ipairs(DB()) do
		if Rules.Matches(rule, item) then
			return rule
		end
	end
	return nil
end

local function LastBagIndex()
	return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

-- Reads one bag slot into an item table, or nil if empty / unmailable.
-- Second return is true when item info isn't cached yet.
function Rules.ReadSlot(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info then
		return nil
	end
	if info.isBound then
		return nil -- soulbound items can't be mailed
	end
	local name, _, quality, ilvl, _, _, _, _, equipLoc, _, _, classID, subclassID, bindType =
		C_Item.GetItemInfo(info.hyperlink)
	if not name then
		if C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(info.itemID)
		end
		return nil, true
	end
	if bindType == 4 then
		return nil -- quest items
	end
	return {
		bag = bag,
		slot = slot,
		itemID = info.itemID,
		link = info.hyperlink,
		icon = info.iconFileID,
		count = info.stackCount,
		locked = info.isLocked,
		name = name,
		quality = info.quality or quality or 1,
		ilvl = ilvl or 0,
		equipLoc = equipLoc,
		classID = classID,
		subclassID = subclassID,
	}
end

--[[ Builds the send plan from the current bags.
Returns {
	groups = { { recipient = name, contact = contact?, items = { item+{rule=rule} } } },
	pending = number of items whose info isn't loaded yet,
	skippedSelf = number of items whose rule points at the current character,
	noRecipient = number of items whose rule has no recipient,
}
]]
function Rules.BuildPlan()
	local plan = { groups = {}, pending = 0, skippedSelf = 0, noRecipient = 0 }
	local byRecipient = {}
	for bag = 0, LastBagIndex() do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local item, pending = Rules.ReadSlot(bag, slot)
			if pending then
				plan.pending = plan.pending + 1
			elseif item and not item.locked then
				local rule = Rules.FirstMatch(item)
				if rule then
					local recipient, contact = Rules.Recipient(rule)
					if not recipient then
						plan.noRecipient = plan.noRecipient + 1
					elseif Names.IsMe(recipient) then
						plan.skippedSelf = plan.skippedSelf + 1
					else
						local key = Names.Key(recipient)
						local group = byRecipient[key]
						if not group then
							group = { recipient = recipient, contact = contact, items = {} }
							byRecipient[key] = group
							table.insert(plan.groups, group)
						end
						item.rule = rule
						item.selected = true
						table.insert(group.items, item)
					end
				end
			end
		end
	end
	table.sort(plan.groups, function(a, b)
		return Names.Key(a.recipient) < Names.Key(b.recipient)
	end)
	return plan
end
