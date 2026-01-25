local logger = require("logger")
logger.info("Applying custom chapter progress separator patch")

local ReaderFooter = require("apps/reader/modules/readerfooter")

local CHAPTER_SEPARATOR = "|"
local ORIGINAL_SEPARATOR = " ⁄⁄ "

local orig_getChapterProgress = ReaderFooter.getChapterProgress

function ReaderFooter:getChapterProgress(get_percentage, pageno)
	local result = orig_getChapterProgress(self, get_percentage, pageno)

	if type(result) == "string" then
		result = " " .. result:gsub(ORIGINAL_SEPARATOR, CHAPTER_SEPARATOR, 1)
	end

	return result
end

logger.info("Custom chapter progress separator patch applied")
