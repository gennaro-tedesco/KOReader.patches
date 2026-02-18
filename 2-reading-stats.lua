local logger = require("logger")
logger.info("Applying reading hours daily patch")

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

		local cutoff_days = 180
		local cutoff_time = os.time() - (cutoff_days * 86400)

		local sql_stmt = string.format(
			[[
                SELECT
                    strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS date,
                    ROUND(SUM(duration), 0) AS seconds
                FROM page_stat
                WHERE start_time > %d
                GROUP BY date
                ORDER BY date DESC
                LIMIT 30;
        ]],
			cutoff_time
		)

		local ok, result = pcall(conn.exec, conn, sql_stmt)
		conn:close()

		if not ok or not result or not result.date then
			return nil, "Failed to query statistics database"
		end

		local max_seconds = 0
		for i = 1, #result.seconds do
			local secs = tonumber(result.seconds[i])
			if secs and secs > max_seconds then
				max_seconds = secs
			end
		end

		if max_seconds == 0 then
			return nil, "No reading statistics available"
		end

		local scrollbar_width = ScrollableContainer:getScrollbarWidth()
		local content_width = w_width - scrollbar_width
		local bar_max_width = content_width - Screen:scaleBySize(140)
		local rows = VerticalGroup:new({})

		for i = 1, #result.date do
			local date_str = tostring(result.date[i])
			local seconds = tonumber(result.seconds[i])

			if date_str and seconds then
				local timestamp = os.time({
					year = tonumber(date_str:sub(1, 4)),
					month = tonumber(date_str:sub(6, 7)),
					day = tonumber(date_str:sub(9, 10)),
					hour = 0,
					min = 0,
					sec = 0,
				})
				local date_label = os.date("%b %d", timestamp)
				local time_str = secsToTimestring(seconds)

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
		local title = HorizontalGroup:new({
			align = "center",
			icon1,
			HorizontalSpan:new({ width = Screen:scaleBySize(5) }),
			icon2,
		})

		local row_height = Screen:scaleBySize(20) + math.floor(w_padding.internal * 0.5)
		local num_items = #result.date
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

function ReadingHoursWindow:onTapClose()
	self:onClose()
	return true
end

Dispatcher:registerAction("show_reading_hours_daily", {
	category = "none",
	event = "ShowReadingHoursDaily",
	title = _("reading times stats"),
	general = true,
})

function ReaderUI:onShowReadingHoursDaily()
	local widget = ReadingHoursWindow:new()
	UIManager:show(widget, "ui", widget.dimen)
end

logger.info("Reading hours daily patch applied")
