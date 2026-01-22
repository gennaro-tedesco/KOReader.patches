local ReaderFont = require("apps/reader/modules/readerfont")
local Font = require("ui/font")
local FontList = require("fontlist")
local UIManager = require("ui/uimanager")
local BD = require("ui/bidi")
local T = require("ffi/util").template
local _ = require("gettext")
local util = require("util")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")

-- 1. Apply the stored UI font setting at startup
local function applyUIFont()
	local font_path = G_reader_settings:readSetting("uifont_path")
	if not font_path then
		return
	end

	-- Try to find the bold variant
	local bold_path = Font.bold_font_variant[font_path]

	local target_regular = font_path
	local target_bold = bold_path or font_path

	-- Override the fontmap
	Font.fontmap.cfont = target_regular
	Font.fontmap.ffont = target_regular
	Font.fontmap.rifont = target_regular
	Font.fontmap.pgfont = target_regular
	Font.fontmap.hfont = target_regular
	Font.fontmap.infofont = target_regular
	Font.fontmap.smallinfofont = target_regular
	Font.fontmap.x_smallinfofont = target_regular
	Font.fontmap.xx_smallinfofont = target_regular

	Font.fontmap.tfont = target_bold
	Font.fontmap.smalltfont = target_bold
	Font.fontmap.x_smalltfont = target_bold
	Font.fontmap.smallinfofontbold = target_bold
end

applyUIFont()

-- 2. UI for selecting the font
local function getUIFontTable(reader_font_instance)
	local fonts_table = {}
	local cre = require("document/credocument"):engineInit()
	local fonts = cre.getFontFaces()

	fonts = reader_font_instance:sortFaceList(fonts)

	for i, font_name in ipairs(fonts) do
		local font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(font_name)
		if not font_filename then
			font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(font_name, nil, true)
		end

		table.insert(fonts_table, {
			text_func = function()
				local text = font_name
				if font_filename and font_faceindex then
					text = FontList:getLocalizedFontName(font_filename, font_faceindex) or text
				end
				if font_filename == G_reader_settings:readSetting("uifont_path") then
					text = text .. "   ★"
				end
				return text
			end,
			callback = function(touchmenu_instance)
				if font_filename then
					G_reader_settings:saveSetting("uifont_path", font_filename)
					G_reader_settings:saveSetting("uifont_name", font_name) -- Save the clean name
					UIManager:show(ConfirmBox:new({
						text = _("UI font changed. You need to restart KOReader to apply the changes."),
						ok_text = _("Restart"),
						ok_callback = function()
							UIManager:nextTick(function()
								os.execute("sleep 1")
								UIManager:quit()
							end)
						end,
						cancel_text = _("Later"),
					}))
				else
					UIManager:show(InfoMessage:new({ text = _("Could not determine filename for this font.") }))
				end
			end,
			radio = true,
			checked_func = function()
				return font_filename == G_reader_settings:readSetting("uifont_path")
			end,
		})
	end
	fonts_table.max_per_page = 5
	return fonts_table
end

local original_addToMainMenu = ReaderFont.addToMainMenu
function ReaderFont:addToMainMenu(menu_items)
	original_addToMainMenu(self, menu_items)

	menu_items.ui_font = {
		text_func = function()
			local current_name = G_reader_settings:readSetting("uifont_name")
			if current_name then
				return T(_("UI font: %1"), BD.wrap(current_name))
			end

			local current_path = G_reader_settings:readSetting("uifont_path")
			if current_path then
				-- Try to resolve the nice name from the path if not saved
				local cre = require("document/credocument"):engineInit()
				local fonts = cre.getFontFaces()
				for _, font_name in ipairs(fonts) do
					local font_filename = cre.getFontFaceFilenameAndFaceIndex(font_name)
					if not font_filename then
						font_filename = cre.getFontFaceFilenameAndFaceIndex(font_name, nil, true)
					end
					if font_filename == current_path then
						-- Found it! Save it for next time to avoid this loop
						G_reader_settings:saveSetting("uifont_name", font_name)
						return T(_("UI font: %1"), BD.wrap(font_name))
					end
				end

				local path_dummy, file = util.splitFilePathName(current_path)
				return T(_("UI font: %1"), BD.wrap(file or _("Custom")))
			else
				return _("UI font")
			end
		end,
		sub_item_table_func = function()
			return getUIFontTable(self)
		end,
	}
end

-- Inject into menu order
local menu_order = require("ui/elements/reader_menu_order")
local has_ui_font = false
for i, v in ipairs(menu_order.typeset) do
	if v == "ui_font" then
		has_ui_font = true
		break
	end
end

if not has_ui_font then
	local original_typeset_order = {}
	for i, v in ipairs(menu_order.typeset) do
		original_typeset_order[i] = v
	end

	menu_order.typeset = {}
	for i, item_id in ipairs(original_typeset_order) do
		table.insert(menu_order.typeset, item_id)
		if item_id == "change_font" then
			table.insert(menu_order.typeset, "ui_font")
		end
	end
end
