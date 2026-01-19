local logger = require("logger")
logger.info("Applying footer glyphs patch")

local userpatch = require("userpatch")
local ReaderFooter = require("apps/reader/modules/readerfooter")

local symbol_prefix = userpatch.getUpValue(ReaderFooter.textOptionTitles, "symbol_prefix")
if symbol_prefix and symbol_prefix.icons then
	symbol_prefix.icons.book_time_to_read = ""
	symbol_prefix.icons.chapter_time_to_read = "⏳"
	symbol_prefix.icons.percentage = nil
end

logger.info("Footer glyphs patch applied")
