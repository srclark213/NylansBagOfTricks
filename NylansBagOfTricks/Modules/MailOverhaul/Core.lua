local _, ns = ...

local MO = ns.RegisterModule("MailOverhaul", {
	name = "Mail Overhaul",
	description = "Replaces the mailbox with a tabbed window: inbox with Open all, an alt and friend address book, and rule-based item sending.",
	-- It takes over the mailbox, which is a lot to spring on someone; opt in.
	defaultEnabled = false,
})

MO.version = ns.version

local DB_SCHEMA = 1

local DEFAULTS = {
	schema = DB_SCHEMA,
	contacts = {},   -- [id] = contact table, see Contacts.lua
	rules = {},      -- ordered array, see Rules.lua
	recent = {},     -- { { name, time } } most recent first
	settings = {
		useMailbox = true,          -- replace Blizzard's mail window with ours
		replaceAutocomplete = true, -- Blizzard window: our suggestions in the "To:" box
		subject = "Mail Overhaul",
	},
}

local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = {}
				ApplyDefaults(target[key], value)
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			ApplyDefaults(target[key], value)
		end
	end
end

function MO.Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	DEFAULT_CHAT_FRAME:AddMessage("|cff66bbffMail Overhaul|r: " .. tostring(msg))
end

-- Tiny callback registry so UI pieces can refresh when data changes.
local listeners = {}

function MO.On(event, fn)
	listeners[event] = listeners[event] or {}
	table.insert(listeners[event], fn)
end

function MO.Fire(event, ...)
	for _, fn in ipairs(listeners[event] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

-- Run fn once the named addon is loaded (immediately if it already is).
function MO.WhenAddOnLoaded(addonName, fn)
	if C_AddOns.IsAddOnLoaded(addonName) then
		fn()
		return
	end
	local waiter = CreateFrame("Frame")
	waiter:RegisterEvent("ADDON_LOADED")
	waiter:SetScript("OnEvent", function(self, _, loaded)
		if loaded == addonName then
			self:UnregisterAllEvents()
			fn()
		end
	end)
end

function MO:OnLoad()
	MailOverhaulDB = MailOverhaulDB or {}
	ApplyDefaults(MailOverhaulDB, DEFAULTS)
	MO.db = MailOverhaulDB
	MO.RegisterSlashCommands()
end

function MO:OnLogin()
	MO.Contacts.RegisterCurrentCharacter()
	MO.WhenAddOnLoaded("Blizzard_MailFrame", function()
		MO.MailHooks.Init()
		MO.Mailbox.Init()
	end)

	local levelWatcher = CreateFrame("Frame")
	levelWatcher:RegisterEvent("PLAYER_LEVEL_UP")
	levelWatcher:SetScript("OnEvent", function(_, _, newLevel)
		-- UnitLevel isn't updated yet when this fires; the payload is the new level.
		MO.Contacts.RegisterCurrentCharacter(newLevel)
	end)
end

-- Only registered while the module is enabled.
function MO.RegisterSlashCommands()
	SLASH_MAILOVERHAUL1 = "/mailoverhaul"
	SLASH_MAILOVERHAUL2 = "/mo"
	SlashCmdList.MAILOVERHAUL = function(msg)
		msg = strtrim(msg or ""):lower()
		if msg == "rules" then
			MO.Mailbox.Show("rules")
		elseif msg == "whoami" then
			MO.Print("Your mail name is detected as '%s'.", MO.Names.GetPlayerFullName() or "?")
		elseif msg == "blizz" or msg == "blizzard" then
			MO.Mailbox.SetEnabled(not MO.db.settings.useMailbox)
			MO.Print("Mailbox window: %s.", MO.db.settings.useMailbox and "Mail Overhaul" or "Blizzard")
		else
			MO.Mailbox.Show("contacts")
		end
	end
end
