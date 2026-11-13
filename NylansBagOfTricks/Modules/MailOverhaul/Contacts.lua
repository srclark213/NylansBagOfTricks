local _, ns = ...
local MO = ns.Modules.MailOverhaul

--[[ Address book.

contact = {
	id        = string,  -- character GUID for alts, "c:<n>" for hand-added contacts
	kind      = "alt" | "contact",
	name      = string,  -- detected full name ("First Last")
	mailName  = string?, -- user override for what to type into the To: box
	nickname  = string?,
	group     = string?,
	note      = string?,
	class     = string?, -- class file, e.g. "MAGE"
	level     = number?,
	faction   = string?, -- "Alliance" / "Horde"
	realm     = string?,
	lastSeen  = number?, -- time()
}
]]
local Contacts = {}
MO.Contacts = Contacts

local Names = MO.Names

local function DB()
	return MO.db.contacts
end

function Contacts.MailName(contact)
	if contact.mailName and contact.mailName ~= "" then
		return contact.mailName
	end
	return contact.name
end

function Contacts.DisplayName(contact)
	local name = Contacts.MailName(contact)
	if contact.nickname and contact.nickname ~= "" then
		return ("%s (%s)"):format(name, contact.nickname)
	end
	return name
end

function Contacts.Get(id)
	return id and DB()[id]
end

function Contacts.IsMe(contact)
	if contact.kind == "alt" and contact.id == UnitGUID("player") then
		return true
	end
	return Names.IsMe(Contacts.MailName(contact))
end

function Contacts.SameFaction(contact)
	return not contact.faction or contact.faction == UnitFactionGroup("player")
end

function Contacts.FindByName(name)
	local key = Names.Key(name)
	if key == "" then
		return nil
	end
	for _, contact in pairs(DB()) do
		if Names.Key(Contacts.MailName(contact)) == key or Names.Key(contact.name) == key then
			return contact
		end
	end
	return nil
end

-- Called on login and level-up: records/refreshes the current character as an alt.
function Contacts.RegisterCurrentCharacter(levelOverride)
	local guid = UnitGUID("player")
	local fullName = Names.GetPlayerFullName()
	if not guid or not fullName then
		return
	end
	local contact = DB()[guid] or { id = guid, kind = "alt" }
	contact.name = fullName
	contact.class = select(2, UnitClass("player"))
	contact.level = levelOverride or UnitLevel("player")
	contact.faction = UnitFactionGroup("player")
	contact.realm = GetRealmName()
	contact.lastSeen = time()
	DB()[guid] = contact
	MO.Fire("CONTACTS_CHANGED")
end

function Contacts.Add(fields)
	local name = Names.Clean(fields.name)
	if name == "" then
		return nil, "Name is required."
	end
	local existing = Contacts.FindByName(name)
	if existing then
		return existing, "Already in the address book."
	end
	local n = 1
	while DB()["c:" .. n] do
		n = n + 1
	end
	local contact = { id = "c:" .. n, kind = "contact", name = name }
	for key, value in pairs(fields) do
		if type(value) == "string" then
			value = Names.Clean(value)
			if value == "" then
				value = nil
			end
		end
		if key ~= "name" and key ~= "id" and key ~= "kind" then
			contact[key] = value
		end
	end
	DB()[contact.id] = contact
	MO.Fire("CONTACTS_CHANGED")
	return contact
end

function Contacts.Update(id, fields)
	local contact = DB()[id]
	if not contact then
		return
	end
	for key, value in pairs(fields) do
		if key ~= "id" and key ~= "kind" then
			if type(value) == "string" then
				value = Names.Clean(value)
				if value == "" then
					value = nil
				end
			end
			-- Alts keep their detected name; edits go to the override.
			if key == "name" and contact.kind == "alt" then
				key = "mailName"
				if value and Names.Equal(value, contact.name) then
					value = nil
				end
			end
			contact[key] = value
		end
	end
	if contact.kind == "contact" and not contact.name then
		contact.name = contact.mailName or "?"
	end
	MO.Fire("CONTACTS_CHANGED")
end

function Contacts.Delete(id)
	if DB()[id] then
		DB()[id] = nil
		MO.Fire("CONTACTS_CHANGED")
	end
end

-- Sorted list: alts first, then contacts by group, then by name.
function Contacts.List()
	local list = {}
	for _, contact in pairs(DB()) do
		table.insert(list, contact)
	end
	table.sort(list, function(a, b)
		if a.kind ~= b.kind then
			return a.kind == "alt"
		end
		local ga, gb = a.group or "", b.group or ""
		if ga ~= gb then
			return ga < gb
		end
		return Names.Key(Contacts.MailName(a)) < Names.Key(Contacts.MailName(b))
	end)
	return list
end

-- Score how well `query` matches a contact; nil = no match. Lower is better.
local function MatchScore(contact, query)
	local mailName = Names.Key(Contacts.MailName(contact))
	local nickname = Names.Key(contact.nickname)
	if mailName:sub(1, #query) == query then
		return 1
	end
	if nickname ~= "" and nickname:sub(1, #query) == query then
		return 2
	end
	-- Prefix of any word (e.g. typing the surname).
	for word in mailName:gmatch("%S+") do
		if word:sub(1, #query) == query then
			return 3
		end
	end
	if mailName:find(query, 1, true) or (nickname ~= "" and nickname:find(query, 1, true)) then
		return 4
	end
	local group, note = Names.Key(contact.group), Names.Key(contact.note)
	if group:find(query, 1, true) or note:find(query, 1, true) then
		return 5
	end
	return nil
end

function Contacts.Search(text, maxResults, includeSelf)
	local query = Names.Key(text)
	if query == "" then
		return {}
	end
	local results = {}
	for _, contact in pairs(DB()) do
		if includeSelf or not Contacts.IsMe(contact) then
			local score = MatchScore(contact, query)
			if score then
				table.insert(results, { contact = contact, score = score })
			end
		end
	end
	table.sort(results, function(a, b)
		if a.score ~= b.score then
			return a.score < b.score
		end
		if a.contact.kind ~= b.contact.kind then
			return a.contact.kind == "alt"
		end
		return Names.Key(Contacts.MailName(a.contact)) < Names.Key(Contacts.MailName(b.contact))
	end)
	local out = {}
	for i = 1, math.min(#results, maxResults or #results) do
		out[i] = results[i].contact
	end
	return out
end

function Contacts.AddTarget()
	if not UnitIsPlayer("target") then
		return nil, "Target a player first."
	end
	local name = Names.GetUnitFullName("target")
	local contact, err = Contacts.Add({
		name = name,
		class = select(2, UnitClass("target")),
		level = UnitLevel("target"),
		faction = UnitFactionGroup("target"),
	})
	return contact, err
end

function Contacts.ImportFriends()
	local added = 0
	if not (C_FriendList and C_FriendList.GetNumFriends) then
		return 0
	end
	for i = 1, C_FriendList.GetNumFriends() do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if info and info.name and info.name ~= "" then
			local _, err = Contacts.Add({ name = info.name, group = "Friends", note = info.notes })
			if not err then
				added = added + 1
			end
		end
	end
	return added
end
