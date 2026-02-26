local logger = require("logger")
logger.info("Applying reading hours patch")

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local ReaderUI = require("apps/reader/readerui")
local Screen = Device.screen
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local SQ3 = require("lua-ljsqlite3/init")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local ReadingHoursWindow = InputContainer:extend({
	modal = true,
	name = "reading_hours_window",
})

function ReadingHoursWindow:init()
	self.show_all_days = G_reader_settings:readSetting("reading_hours_show_all_days") or false
	local screen_width = Screen:getWidth()
	local screen_height = Screen:getHeight()
	local w_width = math.floor(screen_width * 0.7)
	if screen_width > screen_height then
		w_width = math.floor(w_width * screen_height / screen_width)
	end

	local w_font = {
		face = "cfont",
		size = { big = 22, med = 18, small = 15 },
		color = {
			black = Blitbuffer.COLOR_BLACK,
			gray = Blitbuffer.COLOR_GRAY_4,
		},
	}

	local w_padding = {
		internal = Screen:scaleBySize(10),
		external = Screen:scaleBySize(20),
	}

	local function vertical_spacing(h)
		h = h or 1
		return VerticalSpan:new({ width = math.floor(w_padding.internal * h) })
	end

	local function textt(txt, size, color)
		return TextWidget:new({
			text = txt,
			face = Font:getFace(w_font.face, size),
			fgcolor = color or w_font.color.black,
			padding = Screen:scaleBySize(2),
		})
	end

	local function secsToTimestring(secs)
		local h = math.floor(secs / 3600)
		local m = math.floor((secs % 3600) / 60)
		if h == 0 and m < 1 then
			return "< 1m"
		elseif h == 0 then
			return string.format("%dm", m)
		elseif m == 0 then
			return string.format("%dh", h)
		else
			return string.format("%dh %dm", h, m)
		end
	end

	local function buildWindow()
		local settings_dir = DataStorage:getSettingsDir()
		if not settings_dir then
			return nil, "Cannot access settings directory"
		end

		local db_location = settings_dir .. "/statistics.sqlite3"
		local conn = SQ3.open(db_location)
		if not conn then
			return nil, "Statistics database not found"
		end

		local seconds_in_day = 86400
		local days_to_show = 30
		local cutoff_time = os.time() - (days_to_show * seconds_in_day)

		local sql_stmt = string.format(
			[[
                SELECT
                    strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS date,
                    ROUND(SUM(duration), 0) AS seconds
                FROM page_stat
                WHERE start_time > %d
                GROUP BY date
                ORDER BY date DESC;
            ]],
			cutoff_time
		)

		local ok, pre_result = pcall(conn.exec, conn, sql_stmt)
		conn:close()

		if not ok or not pre_result or not pre_result.date then
			return nil, "Failed to query statistics database"
		end

		local lookup = {}
		for i = 1, #pre_result.date do
			lookup[tostring(pre_result.date[i])] = tonumber(pre_result.seconds[i])
		end

		local required_dates = {}
		local tm = os.time()
		for i = 1, days_to_show do
			local date_str = os.date("%Y-%m-%d", tm)
			local seconds = lookup[date_str] or 0
			if self.show_all_days or seconds > 0 then
				table.insert(required_dates, { date_str, seconds })
			end
			tm = tm - seconds_in_day
		end

		local max_seconds = 0
		for _, entry in ipairs(required_dates) do
			local secs = entry[2]
			if secs > max_seconds then
				max_seconds = secs
			end
		end

		if max_seconds == 0 then
			max_seconds = 1
		end

		local scrollbar_width = ScrollableContainer:getScrollbarWidth()
		local content_width = w_width - scrollbar_width
		local bar_max_width = content_width - Screen:scaleBySize(140)
		local rows = VerticalGroup:new({})

		for _, entry in ipairs(required_dates) do
			local date_str = entry[1]
			local seconds = entry[2]

			local timestamp = os.time({
				year = tonumber(date_str:sub(1, 4)),
				month = tonumber(date_str:sub(6, 7)),
				day = tonumber(date_str:sub(9, 10)),
				hour = 0,
				min = 0,
				sec = 0,
			})
			local date_label = os.date("%b %d", timestamp)
			local time_str = seconds == 0 and "---" or secsToTimestring(seconds)

			local date_widget = textt(date_label, w_font.size.small, w_font.color.black)
			local time_widget = textt(time_str, w_font.size.small, w_font.color.black)

			local bar = ProgressWidget:new({
				width = bar_max_width,
				height = Screen:scaleBySize(10),
				percentage = seconds / max_seconds,
				ticks = nil,
				last = nil,
				margin_h = 0,
				margin_v = 0,
				radius = Screen:scaleBySize(3),
				bordersize = 0,
				bgcolor = Blitbuffer.COLOR_WHITE,
				fillcolor = Blitbuffer.COLOR_BLACK,
			})

			local row = HorizontalGroup:new({
				align = "center",
				LeftContainer:new({
					dimen = Geom:new({ w = Screen:scaleBySize(60), h = Screen:scaleBySize(20) }),
					date_widget,
				}),
				HorizontalSpan:new({ width = Screen:scaleBySize(10) }),
				bar,
				HorizontalSpan:new({ width = Screen:scaleBySize(10) }),
				LeftContainer:new({
					dimen = Geom:new({ w = Screen:scaleBySize(50), h = Screen:scaleBySize(20) }),
					time_widget,
				}),
			})

			table.insert(rows, row)
			table.insert(rows, vertical_spacing(0.5))
		end

		local icon_size = Screen:scaleBySize(30)
		local icon1 = IconWidget:new({
			icon = "calendar",
			width = icon_size,
			height = icon_size,
		})
		local icon2 = IconWidget:new({
			icon = "reading",
			width = icon_size,
			height = icon_size,
		})

		local toggle_button = IconWidget:new({
			icon = "appbar.contrast",
			width = icon_size,
			height = icon_size,
			rotation_angle = self.show_all_days and 180 or 0,
		})

		local center_icons = HorizontalGroup:new({
			icon1,
			HorizontalSpan:new({ width = Screen:scaleBySize(5) }),
			icon2,
		})

		local icons_width = center_icons:getSize().w
		local toggle_width = toggle_button:getSize().w
		local total_content = icons_width + toggle_width
		local left_spacer = (content_width - total_content) / 2

		local title = HorizontalGroup:new({
			HorizontalSpan:new({ width = left_spacer }),
			center_icons,
			HorizontalSpan:new({ width = left_spacer }),
			toggle_button,
		})

		local row_height = Screen:scaleBySize(20) + math.floor(w_padding.internal * 0.5)
		local num_items = #required_dates
		local scrollable_height
		if num_items <= 10 then
			scrollable_height = num_items * row_height
		else
			scrollable_height = 10 * row_height
		end

		local scrollable = ScrollableContainer:new({
			dimen = Geom:new({
				w = w_width,
				h = scrollable_height,
			}),
			show_parent = self,
			rows,
		})

		return VerticalGroup:new({
			title,
			vertical_spacing(),
			scrollable,
		})
	end

	local content, error_msg = buildWindow()

	if not content then
		UIManager:show(InfoMessage:new({ text = _(error_msg or "Unknown error") }))
		return
	end

	local frame = FrameContainer:new({
		radius = Screen:scaleBySize(22),
		bordersize = Screen:scaleBySize(2),
		padding = w_padding.external,
		background = Blitbuffer.COLOR_WHITE,
		content,
	})

	self[1] = CenterContainer:new({
		dimen = Screen:getSize(),
		frame,
	})

	self.dimen = Geom:new({
		x = 0,
		y = 0,
		w = screen_width,
		h = screen_height,
	})

	local frame_dimen = frame:getSize()
	local toggle_size = Screen:scaleBySize(30)
	local toggle_padding = w_padding.external
	self.toggle_area = Geom:new({
		x = (screen_width - frame_dimen.w) / 2 + frame_dimen.w - toggle_size - toggle_padding,
		y = (screen_height - frame_dimen.h) / 2 + toggle_padding,
		w = toggle_size + toggle_padding,
		h = toggle_size + toggle_padding,
	})

	if Device:hasDPad() then
		self.key_events.Close = { { Device.input.group.Back } }
	end
	if Device:isTouchDevice() then
		self.ges_events.TapClose = {
			GestureRange:new({
				ges = "tap",
				range = self.dimen,
			}),
		}
	end
end

function ReadingHoursWindow:onShow()
	UIManager:setDirty(self, function()
		return "ui", self[1][1].dimen
	end)
	return true
end

function ReadingHoursWindow:onClose()
	UIManager:close(self)
	return true
end

function ReadingHoursWindow:onToggle()
	local new_state = not self.show_all_days
	G_reader_settings:saveSetting("reading_hours_show_all_days", new_state)
	UIManager:close(self)
	UIManager:show(ReadingHoursWindow:new(), "ui")
end

function ReadingHoursWindow:onTapClose(arg, ges_ev)
	if ges_ev and ges_ev.pos and self.toggle_area:contains(ges_ev.pos) then
		self:onToggle()
	else
		self:onClose()
	end
	return true
end

Dispatcher:registerAction("show_reading_hours_daily", {
	category = "none",
	event = "ShowReadingHoursDaily",
	title = _("Reading times stats"),
	general = true,
})

function ReaderUI:onShowReadingHoursDaily()
	if self.statistics then
		self.statistics:insertDB()
	end
	local widget = ReadingHoursWindow:new()
	UIManager:show(widget, "ui", widget.dimen)
end

logger.info("Reading hours patch applied")
