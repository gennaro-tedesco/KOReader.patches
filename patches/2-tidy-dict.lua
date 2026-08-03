local logger = require("logger")
logger.info("Applying tidy dictionary patch")

local ReaderUI = require("apps/reader/readerui")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local Translator = require("ui/translator")
local _ = require("gettext")

local orig_ReaderUI_registerModule = ReaderUI.registerModule
function ReaderUI:registerModule(name, ui_module, always_active)
	orig_ReaderUI_registerModule(self, name, ui_module, always_active)

	if name == "dictionary" then
		ui_module:addToDictButtons({
			id = "translate",
			text = _("Translate"),
			show_func = function(d)
				return not d.is_wiki_fullpage
			end,
			callback = function(d)
				Translator:showTranslation(d.lookupword, true)
			end,
		})

		ui_module:addToDictButtons({
			id = "dict_counter",
			text = "",
			conditional = true,
			show_func = function(d)
				return not d.is_wiki_fullpage and d.results ~= nil and #d.results > 1
			end,
			callback = function() end,
		})

		logger.info("Tidy dict buttons registered")
	end
end

local orig_DictQuickLookup_buildButtonLayout = DictQuickLookup.buildButtonLayout
function DictQuickLookup:buildButtonLayout()
	if self.is_wiki_fullpage then
		return orig_DictQuickLookup_buildButtonLayout(self)
	end

	local pool = self:_getButtonPool()
	if self.ui and self.ui.dictionary then
		self:populatePluginButtons(pool, {}, {})
	end

	local buttons = {}
	if self.results and #self.results > 1 then
		table.insert(buttons, { pool.prev_dict, pool.dict_counter, pool.next_dict })
	end
	table.insert(buttons, { pool.highlight, pool.translate })
	return buttons
end

local orig_DictQuickLookup_init = DictQuickLookup.init
function DictQuickLookup:init()
	self.displaynb = nil
	orig_DictQuickLookup_init(self)

	if not self.is_wiki_fullpage then
		local dict_counter_btn = self.button_table:getButtonById("dict_counter")
		if dict_counter_btn then
			dict_counter_btn:setText(self.displaynb_custom or "", dict_counter_btn.width)
		end
	end
end

local orig_DictQuickLookup_update = DictQuickLookup.update
function DictQuickLookup:update()
	local orig_displaynb = self.displaynb
	self.displaynb = nil

	orig_DictQuickLookup_update(self)

	self.displaynb = orig_displaynb

	if not self.is_wiki_fullpage then
		local dict_counter_btn = self.button_table:getButtonById("dict_counter")
		if dict_counter_btn then
			dict_counter_btn:setText(orig_displaynb or "", dict_counter_btn.width)
			dict_counter_btn:refresh()
		end
	end
end

local orig_DictQuickLookup_changeDictionary = DictQuickLookup.changeDictionary
function DictQuickLookup:changeDictionary(index, skip_update)
	orig_DictQuickLookup_changeDictionary(self, index, skip_update)
	if self.is_wiki_fullpage then
		self.displaynb_custom = nil
	else
		self.displaynb_custom = self.displaynb
		self.displaynb = nil
	end
end

function DictQuickLookup:addQueryWordToResult() end

logger.info("Tidy dictionary patch applied successfully")
