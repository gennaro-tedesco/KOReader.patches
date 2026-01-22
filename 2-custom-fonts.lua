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
local DictQuickLookup = require("ui/widget/dictquicklookup")

--------------------------------------------------------------------------------
-- 1. SHARED LOGIC
--------------------------------------------------------------------------------

-- Helper to generate a font selection menu table
-- @param reader_font_instance: the ReaderFont instance (self)
-- @param options: table with configuration:
--    setting_key_path (string): name of setting to save the filename/path to (e.g. "uifont_path")
--    setting_key_name (string): name of setting to save the nice name to (e.g. "uifont_name")
--    save_path_as_name (boolean): if true, saves the font name into the path key (for dict behavior)
--    restart_on_change (boolean): if true, prompts for restart. If false, refreshes UI.
--    mark_active_func (function): returns true if the font is currently active
local function getGenericFontTable(reader_font_instance, options)
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
				if options.mark_active_func(font_filename, font_name) then
					text = text .. "   ★"
				end
				return text
			end,
			callback = function(touchmenu_instance)
				local val_to_save = options.save_path_as_name and font_name or font_filename
				if val_to_save then
					G_reader_settings:saveSetting(options.setting_key_path, val_to_save)
					if options.setting_key_name then
						G_reader_settings:saveSetting(options.setting_key_name, font_name)
					end

					if options.restart_on_change then
						UIManager:show(ConfirmBox:new({
							text = _("Font changed. You need to restart KOReader to apply the changes."),
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
						UIManager:setDirty(nil, "ui")
						if touchmenu_instance then
							touchmenu_instance:updateItems()
						end
					end
				else
					UIManager:show(InfoMessage:new({ text = _("Could not determine filename for this font.") }))
				end
			end,
			radio = true,
			checked_func = function()
				return options.mark_active_func(font_filename, font_name)
			end,
		})
	end
	fonts_table.max_per_page = 5
	return fonts_table
end

--------------------------------------------------------------------------------
-- 2. UI FONT LOGIC
--------------------------------------------------------------------------------

-- Apply the stored UI font setting at startup
local function applyUIFont()
	local font_path = G_reader_settings:readSetting("uifont_path")
	if not font_path then
		return
	end

	local bold_path = Font.bold_font_variant[font_path]
	local target_regular = font_path
	local target_bold = bold_path or font_path

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

--------------------------------------------------------------------------------
-- 3. DICTIONARY FONT LOGIC
--------------------------------------------------------------------------------

local original_getHtmlDictionaryCss = DictQuickLookup.getHtmlDictionaryCss

function DictQuickLookup:getHtmlDictionaryCss()
	local selected_font = G_reader_settings:readSetting("dict_font")

	if selected_font then
		local cre = require("document/credocument"):engineInit()
		local font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(selected_font)
		if font_filename then
			local css_justify = G_reader_settings:nilOrTrue("dict_justify") and "text-align: justify;" or ""
			local css = [[
                @font-face {
                    font-family: 'DictCustomFont';
                    src: url(']] .. font_filename .. [[');
                }
                @page { margin: 0; font-family: 'DictCustomFont'; }
                body { margin: 0; line-height: 1.3; font-family: 'DictCustomFont'; ]] .. css_justify .. [[ }
                blockquote, dd { margin: 0 1em; }
                ol, ul, menu { margin: 0; padding: 0 1.7em; }
            ]]
			if self.css then
				return css .. self.css
			end
			return css
		end
	end

	return original_getHtmlDictionaryCss(self)
end

--------------------------------------------------------------------------------
-- 4. MENU INTEGRATION (Unified)
--------------------------------------------------------------------------------

local original_addToMainMenu = ReaderFont.addToMainMenu
function ReaderFont:addToMainMenu(menu_items)
	original_addToMainMenu(self, menu_items)

	-- Dictionary Font Menu Item
	menu_items.dictionary_font = {
		text_func = function()
			local dict_font = G_reader_settings:readSetting("dict_font")
			if dict_font then
				local display_name = dict_font
				-- Try to find localized name
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
			return getGenericFontTable(self, {
				setting_key_path = "dict_font",
				save_path_as_name = true, -- Dictionary patch behavior: saves the name, not path
				restart_on_change = false,
				mark_active_func = function(fname, fparams)
					return fparams == G_reader_settings:readSetting("dict_font")
				end,
			})
		end,
	}

	-- UI Font Menu Item
	menu_items.ui_font = {
		text_func = function()
			local current_name = G_reader_settings:readSetting("uifont_name")
			if current_name then
				return T(_("UI font: %1"), BD.wrap(current_name))
			end

			local current_path = G_reader_settings:readSetting("uifont_path")
			if current_path then
				-- Try to resolve name on the fly
				local cre = require("document/credocument"):engineInit()
				local fonts = cre.getFontFaces()
				for _, font_name in ipairs(fonts) do
					local font_filename = cre.getFontFaceFilenameAndFaceIndex(font_name)
					if not font_filename then
						font_filename = cre.getFontFaceFilenameAndFaceIndex(font_name, nil, true)
					end
					if font_filename == current_path then
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
			return getGenericFontTable(self, {
				setting_key_path = "uifont_path",
				setting_key_name = "uifont_name",
				save_path_as_name = false, -- UI Font behavior: saves the full path
				restart_on_change = true,
				mark_active_func = function(fname, fparams)
					return fname == G_reader_settings:readSetting("uifont_path")
				end,
			})
		end,
	}
end

-- Inject into menu order (Unified)
local menu_order = require("ui/elements/reader_menu_order")
local original_typeset_order = {}
for i, v in ipairs(menu_order.typeset) do
	original_typeset_order[i] = v
end

menu_order.typeset = {}
for i, item_id in ipairs(original_typeset_order) do
	table.insert(menu_order.typeset, item_id)
	if item_id == "change_font" then
		-- Add both items right after the main font change
		table.insert(menu_order.typeset, "dictionary_font")
		table.insert(menu_order.typeset, "ui_font")
	end
end
