local _, ns = ...
local MO = ns.Modules.MailOverhaul

--[[ Sending mail.

SendMail is restricted (needs a click), so every mail goes out from the compose
view's Send button. "Send by rules" builds a queue: each queued mail is staged
(items attached, recipient chosen) and the compose view shows it; Send sends it,
and after MAIL_SEND_SUCCESS the next one is staged.

Events fired (via MO.Fire):
  SENDER_CHANGED            state or queue changed
  QUEUE_STAGED (mail)       a queued mail is ready in the send slots
  MAIL_SENT (recipient, fromQueue)
]]
local Sender = {}
MO.Sender = Sender

Sender.MAX_ATTACHMENTS = ATTACHMENTS_MAX_SEND or 12
-- Blizzard's hidden mail frame resets the send form on MAIL_SEND_SUCCESS; stage after it.
local STAGE_DELAY = 0.5
local MAX_RECENT = 12

Sender.state = "idle" -- "idle" | "sending"
Sender.queue = {}      -- { { recipient, items, subject } }
Sender.index = 0
Sender.message = nil
local sendingRecipient
local sendingFromQueue

local function Changed(message)
	if message ~= nil then
		Sender.message = message
	end
	MO.Fire("SENDER_CHANGED")
end

function Sender.QueueActive()
	return Sender.index > 0 and Sender.index <= #Sender.queue
end

function Sender.Current()
	return Sender.QueueActive() and Sender.queue[Sender.index] or nil
end

function Sender.NumAttached()
	local n = 0
	for i = 1, Sender.MAX_ATTACHMENTS do
		if GetSendMailItem(i) then
			n = n + 1
		end
	end
	return n
end

local function FreeSlot()
	for i = 1, Sender.MAX_ATTACHMENTS do
		if not GetSendMailItem(i) then
			return i
		end
	end
	return nil
end

-- Checks the bag slot still holds the planned item.
local function SlotStillMatches(item)
	local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
	return info and info.itemID == item.itemID and not info.isLocked and not info.isBound
end

-- Attaches bag items into free send slots. Returns how many were attached.
function Sender.AttachItems(items)
	ClearCursor()
	local attached = 0
	for _, item in ipairs(items) do
		local slot = FreeSlot()
		if not slot then
			break
		end
		if SlotStillMatches(item) then
			C_Container.PickupContainerItem(item.bag, item.slot)
			if CursorHasItem() then
				ClickSendMailItemButton(slot)
				if CursorHasItem() then
					ClearCursor() -- couldn't attach (unmailable); put it back
				else
					attached = attached + 1
				end
			end
		end
	end
	return attached
end

local function BuildQueue(plan)
	local queue = {}
	for _, group in ipairs(plan.groups) do
		local mail
		for _, item in ipairs(group.items) do
			if item.selected then
				if not mail or #mail.items >= Sender.MAX_ATTACHMENTS then
					mail = { recipient = group.recipient, contact = group.contact, items = {} }
					table.insert(queue, mail)
				end
				table.insert(mail.items, item)
			end
		end
	end
	return queue
end

local function StageCurrent()
	local mail = Sender.Current()
	if not mail then
		local total = #Sender.queue
		Sender.queue, Sender.index = {}, 0
		Changed(total > 0 and "All rule mail sent." or nil)
		return
	end
	if not MO.Mailbox.AtMailbox() then
		Sender.StopQueue("Mailbox closed.")
		return
	end
	ClearSendMail()
	local attached = Sender.AttachItems(mail.items)
	if attached == 0 then
		MO.Print("Nothing left to attach for %s, skipping.", mail.recipient)
		Sender.index = Sender.index + 1
		StageCurrent()
		return
	end
	mail.attached = attached
	mail.subject = MO.db.settings.subject or "Mail Overhaul"
	Changed(nil)
	MO.Fire("QUEUE_STAGED", mail)
end

function Sender.StartQueue(plan)
	Sender.queue = BuildQueue(plan)
	Sender.index = #Sender.queue > 0 and 1 or 0
	Sender.message = nil
	if Sender.index == 0 then
		Changed("Nothing selected to send.")
		return
	end
	StageCurrent()
end

function Sender.SkipQueued()
	if not Sender.QueueActive() then
		return
	end
	ClearSendMail()
	Sender.index = Sender.index + 1
	StageCurrent()
end

function Sender.StopQueue(message)
	if Sender.QueueActive() then
		ClearSendMail()
	end
	Sender.queue, Sender.index = {}, 0
	Changed(message)
end

--[[ Sends whatever is in the send slots. Must be called from a click.
mail = { recipient, subject, body, money (copper), cod (copper) } ]]
function Sender.Send(mail)
	if Sender.state == "sending" then
		return false
	end
	local recipient = MO.Names.Clean(mail.recipient)
	if recipient == "" then
		MO.Print("Choose who to send to.")
		return false
	end
	local subject = MO.Names.Clean(mail.subject)
	if subject == "" then
		local name = GetSendMailItem(1)
		subject = name or ""
	end
	if subject == "" then
		MO.Print("A subject is required.")
		return false
	end
	SetSendMailMoney(mail.money or 0)
	SetSendMailCOD(mail.cod or 0)
	sendingRecipient = recipient
	local current = Sender.Current()
	sendingFromQueue = current ~= nil and MO.Names.Equal(current.recipient, recipient)
	Sender.state = "sending"
	Changed(nil)
	SendMail(recipient, subject, mail.body or "")
	return true
end

local function RememberRecipient(name)
	local recent = MO.db.recent
	for i = #recent, 1, -1 do
		if MO.Names.Equal(recent[i].name, name) then
			table.remove(recent, i)
		end
	end
	table.insert(recent, 1, { name = name, time = time() })
	while #recent > MAX_RECENT do
		table.remove(recent)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SEND_SUCCESS")
events:RegisterEvent("MAIL_FAILED")
events:RegisterEvent("MAIL_CLOSED")
events:SetScript("OnEvent", function(_, event)
	if event == "MAIL_SEND_SUCCESS" then
		if Sender.state ~= "sending" then
			return
		end
		Sender.state = "idle"
		local recipient, fromQueue = sendingRecipient, sendingFromQueue
		sendingRecipient, sendingFromQueue = nil, nil
		RememberRecipient(recipient)
		MO.Print("Mail sent to %s.", recipient)
		if fromQueue then
			Sender.index = Sender.index + 1
		end
		Changed(nil)
		MO.Fire("MAIL_SENT", recipient, fromQueue)
		if fromQueue then
			C_Timer.After(STAGE_DELAY, StageCurrent)
		end
	elseif event == "MAIL_FAILED" then
		if Sender.state == "sending" then
			Sender.state = "idle"
			Changed("The server rejected the mail. Check the name and try again.")
		end
	elseif event == "MAIL_CLOSED" then
		Sender.state = "idle"
		Sender.queue, Sender.index = {}, 0
		Sender.message = nil
		Changed(nil)
	end
end)
