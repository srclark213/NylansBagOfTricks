local _, ns = ...

-- Shows a popup offering to switch the interface to gamepad mode when a controller is
-- connected, and (optionally) back to keyboard & mouse when the last controller is removed.
-- Switching is done the same way Blizzard's own settings/kiosk code does it: by setting the
-- InputDeviceInterfaceStyle CVar, which fires INPUT_DEVICE_INTERFACE_TRANSITION and swaps the UI live.

local GP = ns.RegisterModule("GamepadPrompt", {
	name = "Gamepad Prompt",
	description = "Offers to switch to gamepad mode when a controller connects, and back to keyboard & mouse when it's removed.",
	savedVariable = "GamepadPromptDB",
	defaults = {
		enabled = true,             -- prompt when a controller connects
		promptOnDisconnect = true,  -- prompt to go back to keyboard & mouse when it disconnects
		checkOnLogin = false,       -- prompt at login if a controller is already plugged in
	},
	options = {
		{ key = "enabled", label = "Prompt when a controller connects",
			tooltip = "Show a popup offering gamepad mode when a controller is plugged in." },
		{ key = "checkOnLogin", label = "Prompt at login",
			tooltip = "Also offer gamepad mode at login if a controller is already plugged in." },
		{ key = "promptOnDisconnect", label = "Prompt when a controller disconnects",
			tooltip = "Offer to switch back to keyboard & mouse when the last controller is removed." },
	},
})

local POPUP_GAMEPAD = "GAMEPADPROMPT_SWITCH_TO_GAMEPAD"
local POPUP_MKB = "GAMEPADPROMPT_SWITCH_TO_MKB"

local GAMEPAD = Enum.InputDeviceInterfaceType.Gamepad
local MKB = Enum.InputDeviceInterfaceType.Mkb

local db
local pendingStyle -- style we want to prompt for once combat ends

local function Print(msg)
	print("|cff33ff99Gamepad Prompt:|r " .. msg)
end

local function IsSupported()
	return InputUtil and InputUtil.IsGamepadUISupported and InputUtil.IsGamepadUISupported()
end

local function CurrentStyle()
	return C_InputInterfaceStyle.GetCurrentStyle()
end

-- True if at least one physical controller is connected. The "combined" device is a virtual
-- device that merges all controllers, so it doesn't count.
local function HasController()
	local ids = C_GamePad.GetAllDeviceIDs()
	if not ids then
		return false
	end
	local combined = C_GamePad.GetCombinedDeviceID and C_GamePad.GetCombinedDeviceID()
	for _, id in ipairs(ids) do
		if id ~= combined then
			return true
		end
	end
	return false
end

local function SwitchTo(style)
	SetCVar("InputDeviceInterfaceStyle", style)
	-- If the CVar couldn't be changed from an addon, point the player at the setting instead.
	C_Timer.After(0.5, function()
		if CurrentStyle() ~= style then
			Print("Couldn't switch automatically. Use Options > Gameplay > Gamepad > \"" .. (ENABLE_GAMEPAD_UI or "Enable Gamepad UI") .. "\".")
		end
	end)
end

StaticPopupDialogs[POPUP_GAMEPAD] = {
	text = "Controller detected.\n\nSwitch to gamepad mode?",
	button1 = YES,
	button2 = NO,
	button3 = "Don't ask again",
	OnAccept = function() SwitchTo(GAMEPAD) end,
	OnAlt = function()
		db.enabled = false
		Print("Won't ask again. Type /gpprompt on to re-enable.")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	exclusive = true,
	preferredIndex = 3,
}

StaticPopupDialogs[POPUP_MKB] = {
	text = "Controller disconnected.\n\nSwitch back to keyboard & mouse mode?",
	button1 = YES,
	button2 = NO,
	button3 = "Don't ask again",
	OnAccept = function() SwitchTo(MKB) end,
	OnAlt = function()
		db.promptOnDisconnect = false
		Print("Won't ask on disconnect again. Type /gpprompt disconnect to re-enable.")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	exclusive = true,
	preferredIndex = 3,
}

local function ShowPrompt(style)
	if InCombatLockdown() then
		-- Swapping the whole UI mid-fight is a bad idea; ask once combat ends.
		pendingStyle = style
		return
	end
	pendingStyle = nil

	if style == GAMEPAD then
		StaticPopup_Hide(POPUP_MKB)
		if not StaticPopup_Visible(POPUP_GAMEPAD) then
			StaticPopup_Show(POPUP_GAMEPAD)
		end
	else
		StaticPopup_Hide(POPUP_GAMEPAD)
		if not StaticPopup_Visible(POPUP_MKB) then
			StaticPopup_Show(POPUP_MKB)
		end
	end
end

local function CheckConnected()
	if db.enabled and CurrentStyle() ~= GAMEPAD and HasController() then
		ShowPrompt(GAMEPAD)
	end
end

local function CheckDisconnected()
	if db.promptOnDisconnect and CurrentStyle() == GAMEPAD and not HasController() then
		ShowPrompt(MKB)
	elseif not HasController() then
		-- Controller went away before the player answered; the question no longer applies.
		StaticPopup_Hide(POPUP_GAMEPAD)
		if pendingStyle == GAMEPAD then
			pendingStyle = nil
		end
	end
end

local RegisterSlashCommands -- defined below

function GP:OnLoad()
	db = self.db
	RegisterSlashCommands()
end

local frame = CreateFrame("Frame")

function GP:OnLogin()
	if not IsSupported() then
		return
	end

	frame:RegisterEvent("GAME_PAD_CONNECTED")
	frame:RegisterEvent("GAME_PAD_DISCONNECTED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")

	if db.checkOnLogin then
		-- Give the UI a moment to settle so the popup isn't lost behind login frames.
		C_Timer.After(2, CheckConnected)
	end
end

frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "GAME_PAD_CONNECTED" then
		-- Device lists can lag the event by a frame.
		C_Timer.After(0.2, CheckConnected)
	elseif event == "GAME_PAD_DISCONNECTED" then
		C_Timer.After(0.2, CheckDisconnected)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingStyle == GAMEPAD then
			CheckConnected()
		elseif pendingStyle == MKB then
			CheckDisconnected()
		end
	elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
		-- Mode changed (by us or via Settings); any open question is now stale.
		StaticPopup_Hide(POPUP_GAMEPAD)
		StaticPopup_Hide(POPUP_MKB)
		pendingStyle = nil
	end
end)

function RegisterSlashCommands()
	SLASH_GAMEPADPROMPT1 = "/gpprompt"
	SlashCmdList.GAMEPADPROMPT = function(msg)
		msg = strtrim(msg or ""):lower()
		if msg == "on" then
			db.enabled = true
			Print("Will prompt when a controller connects.")
		elseif msg == "off" then
			db.enabled = false
			Print("Won't prompt when a controller connects.")
		elseif msg == "disconnect" then
			db.promptOnDisconnect = not db.promptOnDisconnect
			Print("Prompt on disconnect: " .. (db.promptOnDisconnect and "on" or "off"))
		elseif msg == "login" then
			db.checkOnLogin = not db.checkOnLogin
			Print("Check at login: " .. (db.checkOnLogin and "on" or "off"))
		elseif msg == "gamepad" then
			SwitchTo(GAMEPAD)
		elseif msg == "mkb" or msg == "keyboard" then
			SwitchTo(MKB)
		elseif msg == "test" then
			ShowPrompt(CurrentStyle() == GAMEPAD and MKB or GAMEPAD)
		else
			Print("Mode: " .. (CurrentStyle() == GAMEPAD and "gamepad" or "keyboard & mouse")
				.. ", controller connected: " .. (HasController() and "yes" or "no"))
			Print("/gpprompt on | off | disconnect | login | gamepad | mkb | test")
		end
	end
end
