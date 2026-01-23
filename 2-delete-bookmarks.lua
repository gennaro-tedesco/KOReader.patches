local ConfirmBox = require("ui/widget/confirmbox")
local IconButton = require("ui/widget/iconbutton")
local ReaderBookmark = require("apps/reader/modules/readerbookmark")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

local function remove_all(bookmark, bm_menu)
	if #bookmark.ui.annotation.annotations == 0 or bookmark.ui.highlight.select_mode then
		return
	end
	UIManager:show(ConfirmBox:new({
		text = _("Remove selected bookmarks?"),
		ok_text = _("Remove"),
		ok_callback = function()
			for i = #bookmark.ui.annotation.annotations, 1, -1 do
				local item = bookmark.ui.annotation.annotations[i]
				if item.drawer then
					bookmark.ui.highlight:deleteHighlight(i)
				else
					bookmark:removeItemByIndex(i)
				end
			end
			bookmark:updateBookmarkList({}, 1)
		end,
	}))
end

local function add_titlebar_button(bookmark, bm_menu)
	local title_bar = bm_menu.title_bar
	if not title_bar or title_bar._select_all_delete_button then
		return
	end
	local right_button = title_bar.right_button
	if not right_button then
		return
	end
	local right_icon_size = Screen:scaleBySize(DGENERIC_ICON_SIZE * title_bar.right_icon_size_ratio)
	right_button.padding_left = title_bar.button_padding
	right_button:update()
	local button = IconButton:new({
		icon = "delete_bookmarks",
		width = right_icon_size,
		height = right_icon_size,
		padding = title_bar.button_padding,
		padding_left = title_bar.button_padding,
		padding_right = title_bar.button_padding,
		padding_bottom = right_icon_size,
		overlap_offset = { 0, 0 },
		callback = function()
			remove_all(bookmark, bm_menu)
		end,
		allow_flash = false,
		show_parent = title_bar.show_parent,
	})
	local right_size = right_button:getSize()
	local button_size = button:getSize()
	local gap = 20
	local x = title_bar.width - right_size.w - button_size.w - gap
	local y = math.floor((right_size.h - button_size.h) / 2)
	button.overlap_offset = { x, y }
	table.insert(title_bar, button)
	title_bar._select_all_delete_button = button
end

local orig_onShowBookmark = ReaderBookmark.onShowBookmark
function ReaderBookmark:onShowBookmark(...)
	local ok = orig_onShowBookmark(self, ...)
	local bm_menu = self.bookmark_menu and self.bookmark_menu[1]
	if not bm_menu then
		return ok
	end
	add_titlebar_button(self, bm_menu)
	return ok
end
