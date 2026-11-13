local _, ns = ...
local MO = ns.Modules.MailOverhaul

-- Helpers for WoW Forever's "First Last" character names.
-- The surname separator comes from Blizzard's own constants (a space), and
-- NameUtil.GetUnmodifiedUnitFullName is Blizzard's own way of building a full name.
local Names = {}
MO.Names = Names

local function SurnameSeparator()
	local consts = Constants and Constants.CharacterNameSeparatorConsts
	return (consts and consts.CHARACTERNAME_SURNAME_SEPARATOR) or " "
end

function Names.SurnamesEnabled()
	return RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() or false
end

-- Full mail name for a unit ("First Last" when the unit has a surname).
function Names.GetUnitFullName(unit)
	if not UnitExists(unit) then
		return nil
	end
	if NameUtil and NameUtil.GetUnmodifiedUnitFullName then
		local full = NameUtil.GetUnmodifiedUnitFullName(unit)
		if full and full ~= "" then
			return full
		end
	end
	local first, second = (UnitNameUnmodified or UnitName)(unit)
	if second and second ~= "" and Names.SurnamesEnabled() then
		return first .. SurnameSeparator() .. second
	end
	return first
end

function Names.GetPlayerFullName()
	return Names.GetUnitFullName("player")
end

-- Collapse whitespace and trim, without changing case.
function Names.Clean(name)
	if not name then
		return ""
	end
	name = name:gsub("%s+", " ")
	return strtrim(name)
end

-- Case-insensitive comparison key.
function Names.Key(name)
	return strlower(Names.Clean(name))
end

function Names.Equal(a, b)
	return Names.Key(a) == Names.Key(b)
end

function Names.IsMe(name)
	local me = Names.GetPlayerFullName()
	return me ~= nil and Names.Equal(name, me)
end

-- "First Last" -> "First", "Last"
function Names.Split(name)
	name = Names.Clean(name)
	local sep = SurnameSeparator()
	local pos = name:find(sep, 1, true)
	if pos then
		return name:sub(1, pos - 1), name:sub(pos + #sep)
	end
	return name, nil
end

function Names.ClassColored(text, classFile)
	local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if color then
		return color:WrapTextInColorCode(text)
	end
	return text
end
