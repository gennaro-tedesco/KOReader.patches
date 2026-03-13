local logger = require("logger")
logger.info("Applying file browser metadata tree patch")

local Archiver = require("ffi/archiver")
local userpatch = require("userpatch")
local BookList = require("ui/widget/booklist")
local BookInfo = require("apps/filemanager/filemanagerbookinfo")
local FileChooser = require("ui/widget/filechooser")
local DocSettings = require("docsettings")
local ffiUtil = require("ffi/util")
local _ = require("gettext")
local T = ffiUtil.template

local sentinel = "\u{FFFF}"

local function decodeXmlEntities(s)
	return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

local function getPropsFromEpub(filepath)
	local reader = Archiver.Reader:new()
	if not reader:open(filepath) then
		return nil
	end
	for i in reader:iterate() do
	end
	local container = reader:extractToMemory("META-INF/container.xml")
	if not container then
		reader:close()
		return nil
	end
	local opf_path = container:match('full%-path="([^"]+)"')
	if not opf_path then
		reader:close()
		return nil
	end
	local opf = reader:extractToMemory(opf_path)
	reader:close()
	if not opf then
		return nil
	end
	local props = {}
	local raw_title = opf:match("<dc:title[^>]*>%s*(.-)%s*</dc:title>")
	props.title = raw_title and decodeXmlEntities(raw_title) or nil
	local creators = {}
	for creator in opf:gmatch("<dc:creator[^>]*>%s*(.-)%s*</dc:creator>") do
		if creator ~= "" then
			table.insert(creators, decodeXmlEntities(creator))
		end
	end
	if #creators > 0 then
		props.authors = table.concat(creators, "\n")
	end
	props.language = opf:match("<dc:language[^>]*>%s*(.-)%s*</dc:language>")
	local raw_series = opf:match('<meta%s+name="calibre:series"%s+content="([^"]+)"')
		or opf:match('<meta%s+content="([^"]+)"%s+name="calibre:series"')
	props.series = raw_series and decodeXmlEntities(raw_series) or nil
	local subjects = {}
	for subject in opf:gmatch("<dc:subject[^>]*>%s*(.-)%s*</dc:subject>") do
		if subject ~= "" then
			table.insert(subjects, decodeXmlEntities(subject))
		end
	end
	if #subjects > 0 then
		props.keywords = table.concat(subjects, "\n")
	end
	return props
end

local folded_groups = {}

local function split_metadata(value)
	local parts = {}
	for part in value:gmatch("[^,;\n\r]+") do
		local trimmed = part:match("^%s*(.-)%s*$")
		if trimmed ~= "" then
			table.insert(parts, trimmed)
		end
	end
	return parts
end

local function buildItemList(cache)
	local result = {}
	for _, item in ipairs(cache.preamble) do
		table.insert(result, item)
	end
	for _, group in ipairs(cache.groups) do
		local folded = folded_groups[group.key]
		table.insert(result, {
			text = (folded and "\u{25B6} " or "\u{25BC} ") .. group.key,
			path = cache.dir,
			is_header = true,
			group_key = group.key,
			bold = true,
		})
		if not folded then
			for _, item in ipairs(group.items) do
				local title = (item.doc_props and item.doc_props.title) or item.orig_text or item.text
				item.orig_text = item.orig_text or item.text
				item.text = "    " .. title
				table.insert(result, item)
			end
		end
	end
	return result
end

local METADATA_FIELDS = {
	{ id = "authors", text = _("Authors") },
	{ id = "language", text = _("Language") },
	{ id = "series", text = _("Series") },
	{ id = "keywords", text = _("Tags") },
}

local saved_collates = {
	authors = BookList.collates.authors,
	series = BookList.collates.series,
	keywords = BookList.collates.keywords,
}

if G_reader_settings:isTrue("metadata_tree_active") then
	BookList.collates.authors = nil
	BookList.collates.series = nil
	BookList.collates.keywords = nil
end

userpatch.registerPatchPluginFunc("coverbrowser", function(plugin)
	local setting_metadata_mode = false

	local orig_addToMainMenu = plugin.addToMainMenu
	function plugin:addToMainMenu(menu_items)
		orig_addToMainMenu(self, menu_items)

		local dm = menu_items.filemanager_display_mode
		if not dm then
			return
		end

		local orig_classic_checked = dm.sub_item_table[1].checked_func
		dm.sub_item_table[1].checked_func = function()
			if G_reader_settings:isTrue("metadata_tree_active") then
				return false
			end
			return orig_classic_checked()
		end

		table.insert(dm.sub_item_table, 2, {
			text = _("Metadata tree view"),
			radio = true,
			checked_func = function()
				return G_reader_settings:isTrue("metadata_tree_active")
			end,
			callback = function()
				setting_metadata_mode = true
				G_reader_settings:makeTrue("metadata_tree_active")
				BookList.collates.authors = nil
				BookList.collates.series = nil
				BookList.collates.keywords = nil
				plugin.setDisplayMode(self, nil)
				setting_metadata_mode = false
				self.ui.file_chooser:refreshPath()
			end,
		})

		local fc = self.ui.file_chooser
		local sub_item_table = {}
		for i, field in ipairs(METADATA_FIELDS) do
			local id = field.id
			table.insert(sub_item_table, {
				text = field.text,
				radio = true,
				checked_func = function()
					return G_reader_settings:readSetting("metadata_tree_group_by", "authors") == id
				end,
				callback = function()
					G_reader_settings:saveSetting("metadata_tree_group_by", id)
					fc:refreshPath()
				end,
			})
		end
		menu_items.metadata_sort_by = {
			enabled_func = function()
				return G_reader_settings:isTrue("metadata_tree_active")
			end,
			text_func = function()
				local current = G_reader_settings:readSetting("metadata_tree_group_by", "authors")
				for i, field in ipairs(METADATA_FIELDS) do
					if field.id == current then
						return T(_("Metadata group by: %1"), field.text)
					end
				end
				return T(_("Metadata group by: %1"), current)
			end,
			sub_item_table = sub_item_table,
		}
	end

	local orig_setDisplayMode = plugin.setDisplayMode
	function plugin:setDisplayMode(display_mode)
		if not setting_metadata_mode then
			G_reader_settings:makeFalse("metadata_tree_active")
			BookList.collates.authors = saved_collates.authors
			BookList.collates.series = saved_collates.series
			BookList.collates.keywords = saved_collates.keywords
			orig_setDisplayMode(self, display_mode)
			if self.ui and self.ui.file_chooser then
				self.ui.file_chooser:refreshPath()
			end
		else
			orig_setDisplayMode(self, display_mode)
		end
	end
end)

local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local orig_getSortingMenuTable = FileManagerMenu.getSortingMenuTable
function FileManagerMenu:getSortingMenuTable()
	local menu = orig_getSortingMenuTable(self)
	menu.sub_item_table_func = function()
		return orig_getSortingMenuTable(self).sub_item_table
	end
	menu.sub_item_table = nil
	return menu
end

local order = require("ui/elements/filemanager_menu_order")
for i, key in ipairs(order.filemanager_settings) do
	if key == "sort_by" then
		table.insert(order.filemanager_settings, i + 1, "metadata_sort_by")
		break
	end
end

local orig_genItemTable = FileChooser.genItemTable
function FileChooser:genItemTable(dirs, files, path)
	local item_table = orig_genItemTable(self, dirs, files, path)

	if not G_reader_settings:isTrue("metadata_tree_active") then
		self._dir_groups = nil
		return item_table
	end

	local group_by = G_reader_settings:readSetting("metadata_tree_group_by", "authors")
	local dir = path or self.path
	if dir:sub(-1) ~= "/" then
		dir = dir .. "/"
	end

	local preamble = {}
	local groups = {}
	local group_map = {}

	for i, item in ipairs(item_table) do
		if not item.is_file then
			table.insert(preamble, item)
		else
			local props = DocSettings:open(item.path):readSetting("doc_props")
			if not props and item.path:lower():match("%.epub$") then
				props = getPropsFromEpub(item.path)
			end
			props = BookInfo.extendProps(props, item.path)
			item.doc_props = props
			item.orig_text = item.text
			local raw = props and props[group_by]
			local keys
			if not raw or raw == sentinel or raw == "" then
				keys = { _("Unknown") }
			else
				keys = split_metadata(raw)
				if #keys == 0 then
					keys = { _("Unknown") }
				end
			end
			local seen_keys = {}
			for _, key in ipairs(keys) do
				if not seen_keys[key] then
					seen_keys[key] = true
					if not group_map[key] then
						group_map[key] = #groups + 1
						table.insert(groups, { key = key, items = {} })
					end
					table.insert(groups[group_map[key]].items, item)
				end
			end
		end
	end

	self._dir_groups = { dir = dir, group_by = group_by, preamble = preamble, groups = groups }
	return buildItemList(self._dir_groups)
end

local orig_onMenuSelect = FileChooser.onMenuSelect
function FileChooser:onMenuSelect(item)
	if item.is_header then
		folded_groups[item.group_key] = not folded_groups[item.group_key] or nil
		if self._dir_groups then
			self:switchItemTable(nil, buildItemList(self._dir_groups))
		else
			self:refreshPath()
		end
		return true
	end
	return orig_onMenuSelect(self, item)
end

logger.info("File browser metadata tree patch applied")
