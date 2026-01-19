local logger = require("logger")
logger.info("Applying distributed progress bar patch")

local ReaderFooter = require("apps/reader/modules/readerfooter")
local TextWidget = require("ui/widget/textwidget")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local BD = require("ui/bidi")
local Screen = require("device").screen

local orig_updateFooterText = ReaderFooter._updateFooterText

function ReaderFooter:_updateFooterText(force_repaint, full_repaint)
	if not self.settings.all_at_once then
		return orig_updateFooterText(self, force_repaint, full_repaint)
	end

	if self.view.currently_scrolling then
		return
	end

	local items = {}
	for _, gen in ipairs(self.footerTextGenerators) do
		local text = gen(self)
		if text and text ~= "" then
			table.insert(items, BD.wrap(text))
		end
	end

	if #items < 2 then
		return orig_updateFooterText(self, force_repaint, full_repaint)
	end

	local margins_width = 2 * Screen:scaleBySize(self.settings.progress_margin_width)
	local max_text_width
	if self.settings.disable_progress_bar then
		max_text_width = self._saved_screen_width - 2 * self.horizontal_margin
	elseif self.settings.progress_bar_position ~= "alongside" then
		max_text_width = self._saved_screen_width
			- (self.settings.align == "center" and margins_width or 2 * self.horizontal_margin)
	else
		local text_ratio = (100 - self.settings.progress_bar_min_width_pct) * 0.01
		max_text_width = math.floor(text_ratio * self._saved_screen_width - margins_width - self.horizontal_margin)
	end

	local widgets = {}
	local widths = {}
	local total_width = 0
	for _, text in ipairs(items) do
		local w = TextWidget:new({
			text = text,
			face = self.footer_text_face,
			bold = self.settings.text_font_bold,
		})
		table.insert(widgets, w)
		local width = w:getSize().w
		table.insert(widths, width)
		total_width = total_width + width
	end

	if total_width > max_text_width then
		for _, w in ipairs(widgets) do
			w:free()
		end
		return orig_updateFooterText(self, force_repaint, full_repaint)
	end

	local positions = {}
	positions[1] = 0
	positions[#widgets] = max_text_width - widths[#widgets]

	for i = 2, #widgets - 1 do
		local target_center = (i - 1) * max_text_width / (#widgets - 1)
		positions[i] = target_center - widths[i] / 2
	end

	local group = HorizontalGroup:new({})
	for i = 1, #widgets do
		if i > 1 then
			local gap = math.floor(positions[i] - positions[i - 1] - widths[i - 1])
			if gap > 0 then
				table.insert(group, HorizontalSpan:new({ width = gap }))
			end
		end
		table.insert(group, widgets[i])
	end

	if self.footer_text.free then
		self.footer_text:free()
	end
	self.footer_text = group
	self.text_container[1] = group

	if self.settings.disable_progress_bar then
		self.text_width = group:getSize().w
		self.footer_text.height = group:getSize().h
		self.progress_bar.height = 0
		self.progress_bar.width = 0
	elseif self.settings.progress_bar_position ~= "alongside" then
		self.text_width = group:getSize().w
		self.footer_text.height = group:getSize().h
		self.progress_bar.width = math.floor(self._saved_screen_width - margins_width)
	else
		self.text_width = group:getSize().w + self.horizontal_margin
		self.footer_text.height = group:getSize().h
		self.progress_bar.width = math.floor(self._saved_screen_width - margins_width - self.text_width)
	end

	if self.separator_line then
		self.separator_line.dimen.w = self._saved_screen_width - 2 * self.horizontal_margin
	end
	self.text_container.dimen.w = self.text_width
	self.horizontal_group:resetLayout()

	if self.settings.progress_bar_position == "alongside" then
		self:updateFooterContainer()
	end

	if force_repaint then
		local UIManager = require("ui/uimanager")
		UIManager:setDirty(self.view.dialog, "ui", self.footer_content.dimen)
	end
	if full_repaint then
		local UIManager = require("ui/uimanager")
		local Event = require("ui/event")
		self.ui:handleEvent(Event:new("UpdatePos"))
	end
end

logger.info("Distributed progress bar patch applied")
