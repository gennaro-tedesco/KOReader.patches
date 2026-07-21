local logger = require("logger")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local SortWidget = require("ui/widget/sortwidget")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")
local ffiUtil = require("ffi/util")
local T = ffiUtil.template
local _ = require("gettext")

logger.info("Applying mysticon dictionary updater patch")

local MYSTICON_SCRIPT_URL = "https://gennaro-tedesco.github.io/mysticon/script.js"
local MYSTICON_RAW_BASE = "https://raw.githubusercontent.com/gennaro-tedesco/mysticon/master"

local function fetchUrlToString(url)
    local socket = require("socket")
    local socketutil = require("socketutil")
    local http = socket.http
    local ltn12 = require("ltn12")
    local sink = {}
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code = socket.skip(1, http.request{ url = url, sink = ltn12.sink.table(sink) })
    socketutil:reset_timeout()
    if code ~= 200 then
        logger.warn("mysticon: fetch failed for", url, "code:", code)
        return nil
    end
    return table.concat(sink)
end

local function downloadFileTo(url, dest_path)
    local socket = require("socket")
    local socketutil = require("socketutil")
    local http = socket.http
    local ltn12 = require("ltn12")
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code = socket.skip(1, http.request{
        url = url,
        sink = ltn12.sink.file(io.open(dest_path, "w")),
    })
    socketutil:reset_timeout()
    return code == 200
end

-- script.js has no JSON: dictionary entries are JS object literals built via
-- `.map()`. Lua patterns can't do balanced-brace matching, so a single
-- lazy pattern across the whole array would happily skip over entries to
-- find the nearest match elsewhere (verified: it does, and silently
-- mismatches title to the wrong entry). Split into per-entry blocks by
-- brace depth first, then match fields within one block at a time.
local function extractBraceBlocks(text, start_pos)
    local blocks = {}
    local i = start_pos or 1
    local n = #text
    while i <= n do
        if text:sub(i, i) == "{" then
            local depth = 1
            local j = i + 1
            while j <= n and depth > 0 do
                local cj = text:sub(j, j)
                if cj == "{" then depth = depth + 1
                elseif cj == "}" then depth = depth - 1 end
                j = j + 1
            end
            table.insert(blocks, text:sub(i, j - 1))
            i = j
        else
            i = i + 1
        end
    end
    return blocks
end

local function parseMysticonStarDictEntries(js_text)
    local entries = {}
    local books_start = js_text:find("books%s*=%s*%[") or 1
    for _, block in ipairs(extractBraceBlocks(js_text, books_start)) do
        local title = block:match('title:%s*"([^"]-)"')
        local format = block:match('format:%s*"([^"]-)"')
        if title and format == "StarDict" then
            local files_str = block:match('files:%s*%[(.-)%]%s*%.map')
            local prefix = block:match('path:%s*`([^`]-)%${n}`')
            if files_str and prefix then
                local filenames = {}
                local ifo_stem
                for fname in files_str:gmatch('"([^"]-)"') do
                    table.insert(filenames, fname)
                    if fname:match("%.ifo$") then
                        ifo_stem = (fname:gsub("%.ifo$", ""))
                    end
                end
                if ifo_stem then
                    table.insert(entries, { title = title, stem = ifo_stem, prefix = prefix, filenames = filenames })
                end
            end
        end
    end
    return entries
end

local function showStatus(prev_msg, text)
    if prev_msg then
        UIManager:close(prev_msg)
    end
    local msg = InfoMessage:new{ text = text, dismissable = false }
    UIManager:show(msg)
    UIManager:forceRePaint()
    return msg
end

local function updateMysticonDictionary(dictionary_module, ifo, remote)
    local dict_dir, ifo_filename = util.splitFilePathName(ifo.file)
    local local_stem = (ifo_filename:gsub("%.ifo$", ""))
    local tmp_dir = dict_dir .. ".mysticon_update_tmp/"
    util.makePath(tmp_dir)

    local status_msg = showStatus(nil, T(_("Downloading %1…"), ifo.name))
    local ok_all = true
    for i, fname in ipairs(remote.filenames) do
        status_msg = showStatus(status_msg, T(_("Downloading %1 (%2/%3)…"), ifo.name, i, #remote.filenames))
        local url = MYSTICON_RAW_BASE .. "/" .. remote.prefix .. fname
        if not downloadFileTo(url, tmp_dir .. fname) then
            ok_all = false
            break
        end
    end

    if not ok_all then
        UIManager:close(status_msg)
        for name in lfs.dir(tmp_dir) do
            if name ~= "." and name ~= ".." then os.remove(tmp_dir .. name) end
        end
        lfs.rmdir(tmp_dir)
        UIManager:show(InfoMessage:new{ text = _("Download failed. Are you online?") })
        return
    end

    status_msg = showStatus(status_msg, T(_("Replacing %1…"), ifo.name))

    local prefix_lower = local_stem:lower() .. "."
    for name in lfs.dir(dict_dir) do
        if name ~= "." and name ~= ".." and name:lower():sub(1, #prefix_lower) == prefix_lower then
            os.remove(dict_dir .. name)
        end
    end
    for _, fname in ipairs(remote.filenames) do
        os.rename(tmp_dir .. fname, dict_dir .. fname)
    end
    lfs.rmdir(tmp_dir)

    -- `ifo` is the same table instance stored in ReaderDictionary's internal
    -- available_ifos list (not a copy), so mutating its fields here updates
    -- the live dictionary list without needing to force a full rescan.
    local f = io.open(ifo.file, "r")
    if f then
        local content = f:read("*all")
        f:close()
        local new_name = content:match("\nbookname=(.-)\r?\n")
        if new_name then ifo.name = new_name end
        ifo.is_html = content:find("sametypesequence=h", 1, true) ~= nil
        local lang_in, lang_out = content:match("lang=(%a+)-?(%a*)\r?\n?")
        ifo.lang = lang_in and { lang_in = lang_in, lang_out = lang_out } or nil
    end
    dictionary_module:updateSdcvDictNamesOptions()

    UIManager:close(status_msg)
    UIManager:show(InfoMessage:new{ text = T(_("Updated: %1"), ifo.name), timeout = 2 })
end

local function checkMysticonUpdates(dictionary_module, sort_widget)
    local status_msg = showStatus(nil, _("Checking mysticon…"))
    local js_text = fetchUrlToString(MYSTICON_SCRIPT_URL)
    UIManager:close(status_msg)
    if not js_text then
        UIManager:show(InfoMessage:new{ text = _("Could not reach mysticon. Are you online?") })
        return
    end

    local remote_entries = parseMysticonStarDictEntries(js_text)
    local matches = {}
    for _, sort_item in ipairs(sort_widget.item_table) do
        local ifo = sort_item.ifo
        local _, ifo_filename = util.splitFilePathName(ifo.file)
        local local_stem = (ifo_filename:gsub("%.ifo$", "")):lower()
        for _, remote in ipairs(remote_entries) do
            if remote.stem:lower() == local_stem then
                table.insert(matches, { ifo = ifo, remote = remote })
                break
            end
        end
    end

    if #matches == 0 then
        UIManager:show(InfoMessage:new{ text = _("No matching dictionaries found on mysticon."), timeout = 2 })
        return
    end

    local buttons = {}
    local list_dialog
    for _, match in ipairs(matches) do
        table.insert(buttons, {{
            text = match.ifo.name,
            align = "left",
            callback = function()
                UIManager:close(list_dialog)
                updateMysticonDictionary(dictionary_module, match.ifo, match.remote)
            end,
        }})
    end
    list_dialog = ButtonDialog:new{
        title = _("Updates available on mysticon"),
        title_align = "center",
        shrink_unneeded_width = true,
        buttons = buttons,
    }
    UIManager:show(list_dialog)
end

local dictionary_module_ref
local orig_ReaderDictionary_showDictionariesMenu = ReaderDictionary.showDictionariesMenu
function ReaderDictionary:showDictionariesMenu(changed_callback)
    dictionary_module_ref = self
    return orig_ReaderDictionary_showDictionariesMenu(self, changed_callback)
end

local orig_SortWidget_onShowWidgetMenu = SortWidget.onShowWidgetMenu
function SortWidget:onShowWidgetMenu()
    local is_dict_manager = self.item_table[1] ~= nil and self.item_table[1].ifo ~= nil
    if not is_dict_manager then
        return orig_SortWidget_onShowWidgetMenu(self)
    end

    local dialog
    local buttons = {
        {{
            text = _("Sort A to Z"),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                self:sortItems("strcoll")
            end,
        }},
        {{
            text = _("Sort Z to A"),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                self:sortItems("strcoll", true)
            end,
        }},
        {{
            text = _("Sort A to Z (natural)"),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                self:sortItems("natural")
            end,
        }},
        {{
            text = _("Sort Z to A (natural)"),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                self:sortItems("natural", true)
            end,
        }},
        {{
            text = _("Check mysticon for updates"),
            align = "left",
            callback = function()
                UIManager:close(dialog)
                checkMysticonUpdates(dictionary_module_ref, self)
            end,
        }},
    }
    dialog = ButtonDialog:new{
        shrink_unneeded_width = true,
        buttons = buttons,
        anchor = function()
            return self.title_bar.left_button.image.dimen
        end,
    }
    UIManager:show(dialog)
    return true
end

logger.info("mysticon dictionary updater patch applied successfully")
