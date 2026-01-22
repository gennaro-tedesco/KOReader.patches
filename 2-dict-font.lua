local DictQuickLookup = require("ui/widget/dictquicklookup")
local ReaderFont = require("apps/reader/modules/readerfont")
local FontList = require("fontlist")
local UIManager = require("ui/uimanager")
local BD = require("ui/bidi")
local T = require("ffi/util").template
local _ = require("gettext")

local function getDictionaryFontTable(reader_font_instance)
	local fonts_table = {}
	local cre = require("document/credocument"):engineInit()
	local dict_fonts = cre.getFontFaces()

	dict_fonts = reader_font_instance:sortFaceList(dict_fonts)

	if G_reader_settings:isTrue("font_menu_sort_by_recently_selected") then
		local current_dict_font = G_reader_settings:readSetting("dict_font")
		if current_dict_font then
			local util = require("util")
			local idx = util.arrayContains(dict_fonts, current_dict_font)
			if idx then
				table.remove(dict_fonts, idx)
				table.insert(dict_fonts, 1, current_dict_font)
			end
		end
	end

	for _, font_name in ipairs(dict_fonts) do
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
				if font_name == G_reader_settings:readSetting("dict_font") then
					text = text .. "   ★"
				end
				return text
			end,
			callback = function(touchmenu_instance)
				G_reader_settings:saveSetting("dict_font", font_name)
				UIManager:setDirty(nil, "ui")
				if touchmenu_instance then
					touchmenu_instance:updateItems()
				end
			end,
			radio = true,
			checked_func = function()
				return font_name == G_reader_settings:readSetting("dict_font")
			end,
		})
	end

	fonts_table.max_per_page = 5

	return fonts_table
end

local original_addToMainMenu = ReaderFont.addToMainMenu
function ReaderFont:addToMainMenu(menu_items)
	original_addToMainMenu(self, menu_items)

	if menu_items.change_font then
		menu_items.change_font.text_func = function()
			return T(_("Text font: %1"), BD.wrap(self.font_face))
		end
	end

	menu_items.dictionary_font = {
		text_func = function()
			local dict_font = G_reader_settings:readSetting("dict_font")
			if dict_font then
				local display_name = dict_font
				local cre = require("document/credocument"):engineInit()
				local font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(dict_font)
				if not font_filename then
					font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(dict_font, nil, true)
				end
				if font_filename and font_faceindex then
					display_name = FontList:getLocalizedFontName(font_filename, font_faceindex) or display_name
				end
				return T(_("Dictionary font: %1"), BD.wrap(display_name))
			else
				return _("Dictionary font")
			end
		end,
		sub_item_table_func = function()
			return getDictionaryFontTable(self)
		end,
	}
end

local menu_order = require("ui/elements/reader_menu_order")
local original_typeset_order = {}
for i, v in ipairs(menu_order.typeset) do
	original_typeset_order[i] = v
end

menu_order.typeset = {}
for i, item_id in ipairs(original_typeset_order) do
	table.insert(menu_order.typeset, item_id)
	if item_id == "change_font" then
		table.insert(menu_order.typeset, "dictionary_font")
	end
end

function DictQuickLookup:getHtmlDictionaryCss()
	local selected_font = G_reader_settings:readSetting("dict_font")

	local css_justify = G_reader_settings:nilOrTrue("dict_justify") and "text-align: justify;" or ""

	local css
	if selected_font then
		local cre = require("document/credocument"):engineInit()
		local font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(selected_font)
		if font_filename then
			css = [[
                @font-face {
                    font-family: 'DictCustomFont';
                    src: url(']] .. font_filename .. [[');
                }

                @page {
                    margin: 0;
                    font-family: 'DictCustomFont';
                }

                body {
                    margin: 0;
                    line-height: 1.3;
                    font-family: 'DictCustomFont';
                    ]] .. css_justify .. [[
                }

                blockquote, dd {
                    margin: 0 1em;
                }

                ol, ul, menu {
                    margin: 0; padding: 0 1.7em;
                }
            ]]
		end
	end

	if not css then
		css = [[
            @page {
                margin: 0;
            }

            body {
                margin: 0;
                line-height: 1.3;
                ]] .. css_justify .. [[
            }

            blockquote, dd {
                margin: 0 1em;
            }

            ol, ul, menu {
                margin: 0; padding: 0 1.7em;
            }
        ]]
	end

	if self.css then
		return css .. self.css
	end
	return css
end
