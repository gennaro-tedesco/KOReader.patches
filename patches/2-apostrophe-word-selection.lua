local LanguageSupport = require("languagesupport")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local util = require("util")

local apostrophes = {
	["'"] = true,
	["’"] = true,
}

local function isAsciiAlphanumeric(char)
	return char and char:match("^[A-Za-z0-9]$") ~= nil
end

local ApostropheWordSelection = {
	name = "apostrophe_word_selection",
}

function ApostropheWordSelection:supportsLanguage()
	return true
end

function ApostropheWordSelection:onWordSelection(args)
	local callbacks = args.callbacks
	local pos0, pos1 = args.pos0, args.pos1
	local changed = false

	local apostrophe_pos = callbacks.get_prev_char_pos(pos0)
	local left_char = apostrophe_pos and callbacks.get_text_in_range(apostrophe_pos, pos0)
	local apostrophe_end = callbacks.get_next_char_pos(pos1)
	local right_char = apostrophe_end and callbacks.get_text_in_range(pos1, apostrophe_end)

	if apostrophes[left_char] then
		local previous_pos = callbacks.get_prev_char_pos(apostrophe_pos)
		if previous_pos and isAsciiAlphanumeric(callbacks.get_text_in_range(previous_pos, apostrophe_pos)) then
			pos0 = previous_pos
			while true do
				previous_pos = callbacks.get_prev_char_pos(pos0)
				if not previous_pos or not isAsciiAlphanumeric(callbacks.get_text_in_range(previous_pos, pos0)) then
					break
				end
				pos0 = previous_pos
			end
			changed = true
		end
	end

	if apostrophes[right_char] then
		local next_pos = callbacks.get_next_char_pos(apostrophe_end)
		if next_pos and isAsciiAlphanumeric(callbacks.get_text_in_range(apostrophe_end, next_pos)) then
			pos1 = next_pos
			while true do
				next_pos = callbacks.get_next_char_pos(pos1)
				if not next_pos or not isAsciiAlphanumeric(callbacks.get_text_in_range(pos1, next_pos)) then
					break
				end
				pos1 = next_pos
			end
			changed = true
		end
	end

	if changed then
		return { pos0, pos1 }
	end
end

LanguageSupport:registerPlugin(ApostropheWordSelection)

local originalImproveWordSelection = LanguageSupport.improveWordSelection
function LanguageSupport:improveWordSelection(selection)
	local improved = originalImproveWordSelection(self, selection)
	if not improved and self.document and not self.document.info.has_pages and selection.pos0 and selection.pos1 then
		self.document:getTextFromXPointers(selection.pos0, selection.pos1, true)
	end
	return improved
end

local originalCleanSelection = ReaderDictionary.cleanSelection
function ReaderDictionary:cleanSelection(text, is_sane)
	if not text or is_sane then
		return originalCleanSelection(self, text, is_sane)
	end

	local candidate = text:gsub("\u{00A0}", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("’", "'")
	candidate = util.stripPunctuation(candidate)
	local prefix = candidate:match("^([LSDMNTlsdmnt]')") or candidate:match("^([Qq][Uu]')")
	local cleaned = originalCleanSelection(self, text, is_sane)

	if prefix then
		return prefix .. cleaned
	end
	return cleaned
end
