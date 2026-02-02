local logger = require("logger")
logger.info("Applying readings stats patch")

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local ReaderUI = require("apps/reader/readerui")
local Screen = Device.screen
local Size = require("ui/size")
local T = require("ffi/util").template
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local util = require("util")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local N_ = _.ngettext

local quicklookwindow = InputContainer:extend({
	modal = true,
	name = "quick_look_window",
})

function quicklookwindow:init()
	local ReaderStatistics = self.ui.statistics
	local statsEnabled = ReaderStatistics and ReaderStatistics.settings and ReaderStatistics.settings.is_enabled
	local ReaderToc = self.ui.toc

	-- BOOK INFO

	local book_title = ""
	local book_author = ""
	if self.ui.doc_props then
		book_title = self.ui.doc_props.display_title or ""
		book_author = self.ui.doc_props.authors or ""
		if book_author:find("\n") then -- Show first author if multiple authors
			book_author = T(_("%1 et al."), util.splitToArray(book_author, "\n")[1] .. ",")
		end
	end

	-- PAGE COUNT AND BOOK PERCENTAGE

	local book_page = 0
	local book_total = 0
	local book_left = 0
	local book_percentage = 0
	if self.ui.document then
		book_page = self.state.page or 1 -- Current page
		book_total = self.ui.document:getPageCount() or 1 -- Use footer's method
		book_left = book_total - book_page
		book_percentage = (book_page / book_total) * 100 -- Format like %.1f in header_string below
	end

	-- CHAPTER INFO

	local chapter_title = ""
	local chapter_total = 0
	local chapter_left = 0
	local chapter_page = 0
	if ReaderToc then
		chapter_title = ReaderToc:getTocTitleByPage(book_page) or "" -- Chapter name
		chapter_page = ReaderToc:getChapterPagesDone(book_page) or 0
		chapter_page = chapter_page + 1 -- This +1 is to include the page you're looking at
		chapter_total = ReaderToc:getChapterPageCount(book_page) or book_total
		chapter_left = ReaderToc:getChapterPagesLeft(book_page) or book_left
	end

	-- BOOK PAGE TURNS (cuz everything gets reassigned with stable pages),

	local book_pageturn = book_page
	local book_pageturn_total = book_total
	local book_pageturn_left = book_left

	-- STABLE PAGES

	if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
		book_page = self.ui.pagemap:getCurrentPageLabel(true) -- these two are strings.
		book_total = self.ui.pagemap:getLastPageLabel(true)
	end

	-- HIDDEN FLOWS (matches footer's getBookProgress method)

	if self.ui.document and self.ui.document.hasHiddenFlows and self.ui.document:hasHiddenFlows() then
		local flow = self.ui.document:getPageFlow(book_pageturn)
		local page_in_flow = self.ui.document:getPageNumberInFlow(book_pageturn)
		local pages_in_flow = self.ui.document:getTotalPagesInFlow(flow)
		book_pageturn = page_in_flow
		book_pageturn_total = pages_in_flow
	end

	local screen_width = Screen:getWidth()
	local screen_height = Screen:getHeight()
	local w_width = math.floor(screen_width / 2)
	if screen_width > screen_height then
		w_width = math.floor(w_width * screen_height / screen_width)
	end

	-- FONT AND PADDING

	local ui_font = G_reader_settings:readSetting("uifont_path")
	logger.info("stats patch using ui font: " .. ui_font)

	local w_font = {
		face = {
			reg = ui_font,
			bold = ui_font,
			it = ui_font,
			boldit = ui_font,
		},
		size = { big = 25, med = 18, small = 15, tiny = 13 },
		color = {
			black = Blitbuffer.COLOR_BLACK,
			darkGray = Blitbuffer.COLOR_GRAY_1,
			lightGray = Blitbuffer.COLOR_GRAY_4,
		},
	}
	local w_padding = {
		internal = Screen:scaleBySize(10),
		external = Screen:scaleBySize(20),
	}

	-- HELPER FUNCTIONS

	local function secsToTimestring(secs) -- seconds to 'x hrs y mins' format
		local timestring = ""

		local h = math.floor(secs / 3600)
		local m = math.floor((secs % 3600) / 60)
		local h_str = T(N_("1 hr", "%1 hrs", h), h)
		local m_str = T(N_("1 min", "%1 mins", m), m)

		if h == 0 and m < 1 then
			return "less than a minute"
		else
			if h >= 1 then
				timestring = timestring .. h_str .. " "
			end
			if m >= 1 then
				timestring = timestring .. m_str .. " "
			end
			timestring = timestring:sub(1, -2) -- remove the last space
		end

		return timestring
	end

	local function vertical_spacing(h) -- vertical space eq. to h*w_padding.internal
		if h == nil then
			h = 1
		end
		local s = VerticalSpan:new({ width = math.floor(w_padding.internal * h) })
		return s
	end

	local function textt(txt, tfont, tsize, tclr, tpadding) -- creates TextWidget
		if not tclr then
			tclr = w_font.color.black
		end

		local w = TextWidget:new({
			text = txt,
			face = Font:getFace(tfont, tsize),
			fgcolor = tclr,
			bold = false,
			padding = tpadding or Screen:scaleBySize(2),
		})
		return w
	end

	local function getWidth(text, face, size) -- text width
		local t = textt(text, face, size)
		local width = t:getSize().w
		t:free()
		return width
	end

	local function textboxx(txt, tfont, tsize, tclr, twidth, tbold, alignmt, justif) -- creates TextBoxWidget
		if not tclr then
			tclr = w_font.color.black
		end
		if not tbold then
			tbold = false
		end
		if not justif then
			justif = false
		end
		if not alignmt then
			alignmt = "center"
		end
		local w = TextBoxWidget:new({
			text = txt,
			face = Font:getFace(tfont, tsize),
			fgcolor = tclr,
			bold = tbold,
			width = twidth,
			alignment = alignmt,
			justified = justif,
			padding = 0,
		})
		return w
	end

	--============================================
	--'QUICK LOOK' WINDOW
	--============================================

	local function buildQuickLookWindow()
		-- we manually calculate chapter page, chapter total and chapter left in terms of pageturns.
		-- this is because we want progress % to update after every PAGETURN (because that feels more
		-- organic) as opposed to having it update every STABLEPAGE (one single stablepage might spread
		-- across multiple pageturns).

		local chapter_pgturn, chapter_pgturn_left, chapter_pgturn_total = 0, 0, 0
		local nextChapterTickPgturn, previousChapterTickPgturn = 0, 0
		if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() and ReaderToc then -- if stable pages are ON and toc is available
			nextChapterTickPgturn = ReaderToc:getNextChapter(book_pageturn) or (book_pageturn_total + 1)
			previousChapterTickPgturn = ReaderToc:getPreviousChapter(book_pageturn) or 1
			if book_pageturn == 1 or ReaderToc:isChapterStart(book_pageturn) then
				previousChapterTickPgturn = book_pageturn
			end
			chapter_pgturn = book_pageturn - previousChapterTickPgturn + 1
			chapter_pgturn_total = nextChapterTickPgturn - previousChapterTickPgturn
			chapter_pgturn_left = nextChapterTickPgturn - book_pageturn - 1
		else
			chapter_pgturn = chapter_page
			chapter_pgturn_total = chapter_total
			chapter_pgturn_left = chapter_left
		end

		--=== QUICK LOOK WINDOW WIDGETS ===--

		local icon_size = Screen:scaleBySize(40)
		local icon_spacing = Screen:scaleBySize(5)

		function itemname(book_or_ch_name)
			local t = string.lower(book_or_ch_name)
			local widget = textboxx(t, w_font.face.reg, w_font.size.med, w_font.color.black, w_width, false, "left")
			return widget
		end

		-- PROGRESS MODULE

		function progressmodule(pgturn, pgturn_total, st_pageno, st_pagetotal) -- last two args rep. stable pages.
			if st_pageno == nil then
				st_pageno = pgturn
			end -- fallback to page turns if st. pgs. off
			if st_pagetotal == nil then
				st_pagetotal = pgturn_total
			end

			local prog_pct = pgturn / pgturn_total
			local progressbarwidth = math.floor(w_width)
			local prog_bar

			local prog_bar = ProgressWidget:new({
				width = progressbarwidth,
				height = Screen:scaleBySize(2),
				percentage = prog_pct,
				margin_v = 0,
				margin_h = 0,
				radius = 0,
				bordersize = 0,
				fillcolor = w_font.color.black,
				bgcolor = Blitbuffer.COLOR_GRAY,
			})

			local pgXofY_txt = T(_("page %1 of %2"), st_pageno, st_pagetotal)
			local pageXofY = textt(pgXofY_txt, w_font.face.reg, w_font.size.small, w_font.color.darkGray)

			local percentage_display_txt = string.format("%i%%", prog_pct * 100)
			local percentage_display =
				textt(percentage_display_txt, w_font.face.reg, w_font.size.small, w_font.color.darkGray)

			local progressModule = VerticalGroup:new({
				prog_bar,
				HorizontalGroup:new({
					pageXofY,
					HorizontalSpan:new({ width = w_width - pageXofY:getSize().w - percentage_display:getSize().w }),
					percentage_display,
				}),
			})
			return progressModule
		end

		-- TIME READ TODAY / PAGES READ TODAY

		local timeReadToday, pagesReadToday = 0, 0
		local timeReadToday_str, pagesReadToday_str = "", ""
		if self.ui.document then
			timeReadToday, pagesReadToday = ReaderStatistics:getTodayBookStats() -- stats for today across all books
			timeReadToday_str = string.format("%s today", secsToTimestring(timeReadToday))
			pagesReadToday_str = T(N_("1 ", "%1 ", pagesReadToday), pagesReadToday)
		end

		local time_read_today_box = function()
			if not statsEnabled or timeReadToday < 60 then -- if time read < 1 min, hide time_read_today_box
				return nil
			end

			local trt_icon = IconWidget:new({
				icon = "reading",
				width = icon_size,
				height = icon_size,
			})

			local t = string.format("%s · %s", pagesReadToday_str, timeReadToday_str)
			local trt_text =
				textboxx(t, w_font.face.it, w_font.size.small, w_font.color.darkGray, w_width, false, "center")

			local widget = HorizontalGroup:new({
				align = "center",
				trt_icon,
				HorizontalSpan:new({ width = icon_spacing }),
				trt_text,
				HorizontalSpan:new({ width = icon_spacing + icon_size }),
			})

			return widget
		end

		-- TIME LEFT IN CHAPTER/BOOK

		local function timeLeft_secs(pages)
			local avgTimePerPgturn = 0
			if statsEnabled then
				avgTimePerPgturn = ReaderStatistics.avg_time
			end
			local total_secs = avgTimePerPgturn * pages
			return total_secs
		end

		local book_timeLeft = "calculating time"
		local chapter_timeLeft = "calculating time"
		if ReaderStatistics.avg_time and ReaderStatistics.avg_time > 0 then
			book_timeLeft = secsToTimestring(timeLeft_secs(book_pageturn_left + 1)) -- +1 to include current page when calc. time left
			chapter_timeLeft = secsToTimestring(timeLeft_secs(chapter_pgturn_left + 1))
		end

		function time_left_display(timeleftstring, book_or_ch)
			local tldfont = w_font.face.boldit
			if not statsEnabled or timeReadToday < 60 then
				tldfont = w_font.face.it
			end

			local displayText = string.format("%s left in %s", timeleftstring, book_or_ch)
			if not statsEnabled then
				displayText = string.format("-- left in %s", book_or_ch)
			end

			local tldWidth = getWidth(displayText, tldfont, w_font.size.small)
			if tldWidth > w_width then
				w_width = tldWidth + Screen:scaleBySize(10)
			end -- monospace fonts take up more space

			local widget = textt(displayText, tldfont, w_font.size.small, w_font.color.darkGray)

			return widget
		end

		local chapter_icon = IconWidget:new({
			icon = "chapter",
			width = icon_size,
			height = icon_size,
		})

		local chapter_text = textboxx(
			string.lower(chapter_title),
			w_font.face.bold,
			w_font.size.med,
			w_font.color.black,
			w_width,
			true,
			"center"
		)

		local chapter_title_widget = HorizontalGroup:new({
			align = "center",
			chapter_icon,
			HorizontalSpan:new({ width = icon_spacing }),
			chapter_text,
			HorizontalSpan:new({ width = icon_spacing + icon_size }),
		})

		local book_icon = IconWidget:new({
			icon = "book_progress",
			width = icon_size,
			height = icon_size,
		})

		local book_text = textboxx(
			string.lower(book_title),
			w_font.face.bold,
			w_font.size.med,
			w_font.color.black,
			w_width,
			true,
			"center"
		)

		local book_title_widget = HorizontalGroup:new({
			align = "center",
			book_icon,
			HorizontalSpan:new({ width = icon_spacing }),
			book_text,
			HorizontalSpan:new({ width = icon_spacing + icon_size }),
		})

		local tleftc = time_left_display(chapter_timeLeft, "chapter")
		local tleftb = time_left_display(book_timeLeft, "book")
		local trtbox = time_read_today_box()
		local progModule_book = progressmodule(book_pageturn, book_pageturn_total, book_page, book_total)
		local progModule_ch = progressmodule(chapter_pgturn, chapter_pgturn_total, chapter_page, chapter_total)

		local quickLookWindow = VerticalGroup:new({
			chapter_title_widget,
			vertical_spacing(),
			progModule_ch,
			vertical_spacing(),
			tleftc,
			vertical_spacing(),
			vertical_spacing(),
			book_title_widget,
			vertical_spacing(),
			progModule_book,
			vertical_spacing(),
			tleftb,
			vertical_spacing(),
		})

		if trtbox then
			table.insert(quickLookWindow, vertical_spacing())
			local separator = LineWidget:new({
				dimen = Geom:new({
					w = w_width,
					h = Screen:scaleBySize(1),
				}),
				background = w_font.color.lightGray,
			})
			table.insert(quickLookWindow, separator)
			table.insert(quickLookWindow, vertical_spacing(0.5))
			table.insert(quickLookWindow, trtbox)
		end

		return quickLookWindow
	end

	--==================//////////==================--

	local frameRadius = Screen:scaleBySize(22)
	local framePadding = w_padding.external

	local WindowToBeDisplayed = buildQuickLookWindow()

	local final_frame = FrameContainer:new({
		radius = frameRadius,
		bordersize = Screen:scaleBySize(2),
		padding = framePadding,
		padding_top = math.floor(w_padding.external / 2.1),
		padding_bottom = math.floor(w_padding.external / 1.1),
		background = Blitbuffer.COLOR_WHITE,
		WindowToBeDisplayed,
	})

	self[1] = CenterContainer:new({
		dimen = Screen:getSize(),
		VerticalGroup:new({
			final_frame,
		}),
	})

	-- taps and keypresses

	if Device:hasKeys() then
		self.key_events.AnyKeyPressed = { { Device.input.group.Any } }
	end
	if Device:isTouchDevice() then
		self.ges_events.Swipe = {
			GestureRange:new({
				ges = "swipe",
				range = function()
					return self.dimen
				end,
			}),
		}
		self.ges_events.Tap = {
			GestureRange:new({
				ges = "tap",
				range = function()
					return self.dimen
				end,
			}),
		}
		self.ges_events.MultiSwipe = {
			GestureRange:new({
				ges = "multiswipe",
				range = function()
					return self.dimen
				end,
			}),
		}
	end
end

function quicklookwindow:onTap()
	UIManager:close(self)
end

function quicklookwindow:onSwipe(arg, ges_ev)
	if ges_ev.direction == "south" then
		-- Allow easier closing with swipe up/down
		self:onClose()
	elseif ges_ev.direction == "east" or ges_ev.direction == "west" or ges_ev.direction == "north" then
		-- -- no use for now
		-- do end -- luacheck: ignore 541
		self:onClose()
	else -- diagonal swipe
		self:onClose()
	end
end

function quicklookwindow:onClose()
	UIManager:close(self)
	return true
end

quicklookwindow.onAnyKeyPressed = quicklookwindow.onClose
quicklookwindow.onMultiSwipe = quicklookwindow.onClose

function quicklookwindow:onShow()
	UIManager:setDirty(self, function()
		return "ui", self[1][1][1].dimen
	end)
	return true
end

function quicklookwindow:onCloseWidget()
	if self[1] and self[1][1] and self[1][1][1] then
		UIManager:setDirty(nil, function()
			return "ui", self[1][1][1].dimen
		end)
	end
end

-- ADD TO DISPATCHER

Dispatcher:registerAction("quicklookbox_action", {
	category = "none",
	event = "QuickLook",
	title = _("Stats"),
	general = true,
})

function ReaderUI:onQuickLook()
	if self.statistics then
		self.statistics:insertDB()
	end

	local widget = quicklookwindow:new({
		ui = self,
		document = self.document,
		state = self.view and self.view.state,
	})

	UIManager:show(widget, "ui", widget.dimen)
end

logger.info("Readings stats patch applied")
