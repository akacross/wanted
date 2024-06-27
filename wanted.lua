script_name("wanted")
script_author("akacross")
script_version("0.5.24")
script_url("https://akacross.net/")

local scriptPath = thisScript().path
local scriptName = thisScript().name
local scriptVersion = thisScript().version

-- Requirements
require 'lib.moonloader'
local ffi = require 'ffi'
local effil = require 'effil'
local mem = require 'memory'
local wm = require 'lib.windows.message'
local imgui = require 'mimgui'
local encoding = require 'encoding'
local sampev = require 'lib.samp.events'
local fa = require 'fAwesome6'
local dlstatus = require 'moonloader'.download_status

-- Encoding
encoding.default = 'CP1251'
local u8 = encoding.UTF8

-- Paths
local workingDir = getWorkingDirectory()
local configDir = workingDir .. '\\config\\'
local cfgFile = configDir .. 'wanted.json'

-- URLs
local url = "https://raw.githubusercontent.com/akacross/wanted/main/"
local scriptUrl = url .. "wanted.lua"
local updateUrl = url .. "wanted.txt"

-- Libs
local wanted = {}
local wanted_defaultSettings = {
    autoCheckUpdate = false,
    updateInProgress = false,
    lastVersion = "Unknown",
    AutoSave = true,
    Enabled = true,
    Stars = false,
    Timer = 5,
    WindowPos = {x = 500, y = 500}
}

local ped, h = playerPed, playerHandle
local wantedlist = nil
local last_wanted = 0
local last_timer = nil
local commandSent = false

local new, str, sizeof = imgui.new, ffi.string, ffi.sizeof
local menu = {
    settings = new.bool(false),
    confirm = new.bool(false)
}
local mainc = imgui.ImVec4(0.98, 0.26, 0.26, 1.00)
local windowSize = {x = 0, y = 0}
local tempOffset = {x = 0, y = 0}
local selectedbox = false
local confirmData = {['update'] = {status = false}}

local function handleConfigFile(path, defaults, configVar, ignoreKeys)
	ignoreKeys = ignoreKeys or {}
    if doesFileExist(path) then
        local config, err = loadConfig(path)
        if not config then
            print("Error loading config: " .. err)

            local newpath = path:gsub("%.[^%.]+$", ".bak")
            local success, err2 = os.rename(path, newpath)
            if not success then
                print("Error renaming config: " .. err2)
                os.remove(path)
            end
            handleConfigFile(path, defaults, configVar)
        else
            local result = ensureDefaults(config, defaults, false, ignoreKeys)
            if result then
                local success, err3 = saveConfig(path, config)
                if not success then
                    print("Error saving config: " .. err3)
                end
            end
            return config
        end
    else
        local result = ensureDefaults(configVar, defaults, true)
        if result then
            local success, err = saveConfig(path, configVar)
            if not success then
                print("Error saving config: " .. err)
            end
        end
    end
    return configVar
end

function main()
    createDirectory(configDir)
    wanted = handleConfigFile(cfgFile, wanted_defaultSettings, wanted)

    repeat wait(0) until isSampAvailable()
    if wanted.updateInProgress then
        formattedAddChatMessage(string.format("You have successfully upgraded from Version: %s to %s", wanted.lastVersion, scriptVersion), -1)
        wanted.updateInProgress = false

        local success, err = saveConfig(cfgFile, wanted)
        if not success then print("Error saving config: " .. err) end
    end
    if wanted.autoCheckUpdate then checkForUpdate() end

    sampRegisterChatCommand('wanted.settings', function()
        if wanted.updateInProgress then
            formattedAddChatMessage("Update in progress. Please wait a moment.", -1)
            return
        end
        menu.settings[0] = not menu.settings[0]
    end)

    sampRegisterChatCommand('wanted', function()
        if not wanted.Enabled then sampSendChat("/wanted") return end
        sampAddChatMessage("__________WANTED LIST__________", 0xFF8000)
        if not wantedlist then
            sampAddChatMessage("No current wanted suspects.", -1)
        else
            for _, v in pairs(wantedlist) do
                sampAddChatMessage(string.format("%s (%d): {b4b4b4}%d outstanding %s.", v.name, v.id, v.charges, v.charges == 1 and "charge" or "charges"), -1)
            end
        end
        sampAddChatMessage("________________________________", 0xFF8000)
    end)

    while true do wait(0)
        if sampGetGamestate() ~= 3 and wantedlist then wantedlist = nil end
        if wanted.Enabled and wanted.Timer <= localClock() - last_wanted then
            sampSendChat("/wanted")
            last_wanted = localClock()
            commandSent = true
        end
    end
end

function onScriptTerminate(scr, quitGame)
    if scr == script.this then
        if wanted.AutoSave then
            local success, err = saveConfig(cfgFile, wanted)
            if not success then print("Error saving config: " .. err) end
        end
    end
end

function onWindowMessage(msg, wparam, lparam)
    if wparam == VK_ESCAPE and menu.settings[0] then
        if msg == wm.WM_KEYDOWN then
            consumeWindowMessage(true, false)
        end
        if msg == wm.WM_KEYUP then
            menu.settings[0] = false
        end
    end
end

function sampev.onShowTextDraw(id, data)
    if data.text:match("~r~Objects loading...") then
        last_timer = wanted.Timer
        wanted.Timer = 15
    end

    if data.text:match("~g~Objects loaded!") then
        wanted.Timer = last_timer
    end
end

function sampev.onServerMessage(color, text)
    if wanted.Enabled or commandSent then
        if text:match("You're not a Lawyer / Cop / FBI!") and color == -1347440726 then
            wanted.Enabled = false
        end

        local nickname = text:match("HQ: (.+) has been processed, was arrested.")
        if nickname and wantedlist and color == 641859242 then
            for k, v in pairs(wantedlist) do
                if v.name:match(nickname) then
                    table.remove(wantedlist, k)
                end
            end
        end

        if color == -8388353 then
            if text:match("__________WANTED LIST__________") then
                wantedlist = nil
                return false
            end

            if text:match("________________________________") then
                commandSent = false
                return false
            end
        end

        if color == -86 then
            if text:match("No current wanted suspects.") then
                return false
            end

            local nickname, playerid, charges = text:match("(.+) %((%d+)%): %{b4b4b4%}(%d+) outstanding charge[s]?%.")
            if nickname and playerid and charges then
                wantedlist = wantedlist or {}
                table.insert(wantedlist, {
                    name = nickname,
                    id = tonumber(playerid),
                    charges = tonumber(charges)
                })
                return false
            end
        end
    else
        if ((text:match("LSPD MOTD: (.+)") or text:match("SASD MOTD: (.+)") or text:match("FBI MOTD: (.+)") or text:match("ARES MOTD: (.+)")) and not text:find("SMS:") and not text:find("Advertisement:") and color == -65366) or (text:match("%* You are now a Lawyer, type /help to see your new commands.") and color == 869072810) then
            wanted.Enabled = true
        end
    end
end

imgui.OnInitialize(function()
    apply_custom_style()

    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    config.GlyphMinAdvanceX = 14
    local builder = imgui.ImFontGlyphRangesBuilder()
    local list = {
        "STAR",
        "POWER_OFF",
        "FLOPPY_DISK",
        "REPEAT",
        "ERASER",
        "RETWEET",
        "CIRCLE_CHECK",
        "CIRCLE_XMARK"
    }
    for _, b in ipairs(list) do
        builder:AddText(fa(b))
    end
    defaultGlyphRanges1 = imgui.ImVector_ImWchar()
    builder:BuildRanges(defaultGlyphRanges1)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(fa.get_font_data_base85("solid"), 14, config, defaultGlyphRanges1[0].Data)

    imgui.GetIO().IniFilename = nil
end)

imgui.OnFrame(function()
    return wanted.Enabled and not isPauseMenuActive() and not sampIsScoreboardOpen() and sampGetChatDisplayMode() > 0 and not isKeyDown(VK_F10)
end,
function()
    local newPos, status = imgui.handleWindowDragging(wanted.WindowPos, {x = windowSize.x / 2, y = windowSize.y / 2}, windowSize, menu.settings[0])
    if status then wanted.WindowPos = newPos end
    imgui.SetNextWindowPos(wanted.WindowPos, imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.110, 0.467, 0.702, 1.0))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 2.0)
    if imgui.Begin(scriptName, nil, imgui.WindowFlags.NoDecoration + imgui.WindowFlags.AlwaysAutoResize) then
        if not wantedlist then
            imgui.TextColoredRGB("No current wanted suspects.")
        else
            for _, v in pairs(wantedlist) do
                local stars = wanted.Stars and string.rep(fa.STAR, v.charges) or string.format("%d outstanding %s.", v.charges, v.charges == 1 and "charge" or "charges")
                imgui.TextColoredRGB(string.format("%s (%d): {%s}%s", v.name, v.id, v.charges == 6 and "FF0000FF" or "B4B4B4", stars))
            end
        end
        windowSize = imgui.GetWindowSize()
    end
    imgui.PopStyleVar()
    imgui.PopStyleColor()
    imgui.End()
end).HideCursor = true

imgui.OnFrame(function() return menu.settings[0] end,
function()
    local title = string.format("%s %s Settings - Version: %s", fa.STAR, firstToUpper(scriptName), scriptVersion)
    local width, height = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
    imgui.Begin(title, menu.settings, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.AlwaysAutoResize)
        imgui.BeginChild("##1", imgui.ImVec2(272, 41), true)

        imgui.SetCursorPos(imgui.ImVec2(0, 0))
        if imgui.CustomButtonWithTooltip(
            fa.POWER_OFF..'##1',
            wanted.Enabled and imgui.ImVec4(0.15, 0.59, 0.18, 0.7) or imgui.ImVec4(1, 0.19, 0.19, 0.5),
            wanted.Enabled and imgui.ImVec4(0.15, 0.59, 0.18, 0.5) or imgui.ImVec4(1, 0.19, 0.19, 0.3),
            wanted.Enabled and imgui.ImVec4(0.15, 0.59, 0.18, 0.4) or imgui.ImVec4(1, 0.19, 0.19, 0.2),
            imgui.ImVec2(50.0, 40.0),
            "Toggle Wanted Menu"
        ) then
            wanted.Enabled = not wanted.Enabled
        end

        imgui.SetCursorPos(imgui.ImVec2(51, 0))
        if imgui.CustomButtonWithTooltip(
            fa.FLOPPY_DISK,
            imgui.ImVec4(0.16, 0.16, 0.16, 0.9),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 0.5),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 1),
            imgui.ImVec2(50.0, 40.0),
            'Save configuration'
        ) then
            local success, err = saveConfig(cfgFile, wanted)
            if not success then
                print("Error saving config: " .. err)
            end
        end

        imgui.SetCursorPos(imgui.ImVec2(101, 0))
        if imgui.CustomButtonWithTooltip(
            fa.REPEAT,
            imgui.ImVec4(0.16, 0.16, 0.16, 0.9),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 0.5),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 1),
            imgui.ImVec2(50.0, 40.0),
            'Reload configuration'
        ) then
            wanted = handleConfigFile(cfgFile, wanted_defaultSettings, wanted)
        end

        imgui.SetCursorPos(imgui.ImVec2(151, 0))
        if imgui.CustomButtonWithTooltip(
            fa.ERASER,
            imgui.ImVec4(0.16, 0.16, 0.16, 0.9),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 0.5),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 1),
            imgui.ImVec2(50.0, 40.0),
            'Load default configuration'
        ) then
            ensureDefaults(wanted, wanted_defaultSettings, true)
        end

        imgui.SetCursorPos(imgui.ImVec2(201, 0))
        if imgui.CustomButtonWithTooltip(
            fa.RETWEET .. ' Update',
            imgui.ImVec4(0.16, 0.16, 0.16, 0.9),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 0.5),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 1),
            imgui.ImVec2(70.0, 40.0),
            'Check for update)'
        ) then
            checkForUpdate()
        end

        imgui.EndChild()

        imgui.SetCursorPos(imgui.ImVec2(0, 60))
        imgui.BeginChild("##2", imgui.ImVec2(272, 55), true)

        if imgui.Checkbox('Stars', new.bool(wanted.Stars)) then
            wanted.Stars = not wanted.Stars
        end
        imgui.SameLine()
        imgui.PushItemWidth(50)
        local timer = new.float[1](wanted.Timer)
        if imgui.DragFloat('Refresh Rate', timer, 1, 2, 10, "%.f") then
            wanted.Timer = timer[0]
        end
        imgui.PopItemWidth()

        if imgui.Checkbox('Auto-Update', new.bool(wanted.autoCheckUpdate)) then
            wanted.autoCheckUpdate = not wanted.autoCheckUpdate
        end
        imgui.SameLine()
        if imgui.Checkbox('Auto-Save', new.bool(wanted.AutoSave)) then
            wanted.AutoSave = not wanted.AutoSave
        end

        imgui.EndChild()
    imgui.PopStyleVar()
    imgui.End()
end)

local function handleButton(label, action, width)
    width = width or 85
    if imgui.CustomButton(label, imgui.ImVec4(0.16, 0.16, 0.16, 0.9), imgui.ImVec4(0.40, 0.12, 0.12, 1), imgui.ImVec4(0.30, 0.08, 0.08, 1), imgui.ImVec2(width, 45)) then
        action()
        status = false
        menu.confirm[0] = false
    end
end

imgui.OnFrame(function() return menu.confirm[0] end, function()
    local io = imgui.GetIO()
    local center = imgui.ImVec2(io.DisplaySize.x / 2, io.DisplaySize.y / 2)
    imgui.SetNextWindowPos(center, imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.Begin('', menu.confirm, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.AlwaysAutoResize)
    if not imgui.IsWindowFocused() then imgui.SetNextWindowFocus() end
    for n, t in pairs(confirmData) do
        if t.status then
            if n == 'update' then
                imgui.Text('Do you want to update this script?')
                handleButton(fa.CIRCLE_CHECK .. ' Update', function()
                    updateScript()
                    t.status = false
                end)
                imgui.SameLine()
                handleButton(fa.CIRCLE_XMARK .. ' Cancel', function()
                    t.status = false
                end)
            end
        end
    end
    imgui.End()
end)

function checkForUpdate()
	asyncHttpRequest('GET', updateUrl, nil,
		function(response)
            local updateVersion = response.text:match("version: (.+)")
            if updateVersion and compareVersions(scriptVersion, updateVersion) == -1 then
                confirmData['update'].status = true
                menu.confirm[0] = true
            end
		end,
		function(err)
            print(err)
		end
	)
end

function updateScript()
    wanted.updateInProgress = true
    wanted.lastVersion = scriptVersion
    downloadFiles({{url = scriptUrl, path = scriptPath, replace = true}}, function(result)
        if result then
            formattedAddChatMessage("Update downloaded successfully! Reloading the script now.", -1)
            thisScript():reload()
        end
    end)
end

function formattedAddChatMessage(string, color)
    sampAddChatMessage(string.format("{ABB2B9}[%s]{FFFFFF} %s", firstToUpper(scriptName), string), color)
end

function firstToUpper(string)
    return (string:gsub("^%l", string.upper))
end

function downloadFiles(table, onCompleteCallback)
    local downloadsInProgress = 0
    local downloadsStarted = false
    local callbackCalled = false

    local function download_handler(id, status, p1, p2)
        if status == dlstatus.STATUS_ENDDOWNLOADDATA then
            downloadsInProgress = downloadsInProgress - 1
        end

        if downloadsInProgress == 0 and onCompleteCallback and not callbackCalled then
            callbackCalled = true
            onCompleteCallback(downloadsStarted)
        end
    end

    for _, file in ipairs(table) do
        if not doesFileExist(file.path) or file.replace then
            downloadsInProgress = downloadsInProgress + 1
            downloadsStarted = true
            downloadUrlToFile(file.url, file.path, download_handler)
        end
    end

    if not downloadsStarted and onCompleteCallback and not callbackCalled then
        callbackCalled = true
        onCompleteCallback(downloadsStarted)
    end
end

function loadConfig(filePath)
    local file = io.open(filePath, "r")
    if not file then
        return nil, "Could not open file."
    end

    local content = file:read("*a")
    file:close()

    if not content or content == "" then
        return nil, "Config file is empty."
    end

    local success, decoded = pcall(decodeJson, content)
    if success then
        if next(decoded) == nil then
            return nil, "JSON format is empty."
        else
            return decoded, nil
        end
    else
        return nil, "Failed to decode JSON: " .. decoded
    end
end

function saveConfig(filePath, config)
    local file = io.open(filePath, "w")
    if not file then
        return false, "Could not save file."
    end
    file:write(encodeJson(config, true))
    file:close()
    return true
end

function ensureDefaults(config, defaults, reset, ignoreKeys)
    ignoreKeys = ignoreKeys or {}
    local status = false

    local function isIgnored(key)
        for _, ignoreKey in ipairs(ignoreKeys) do
            if key == ignoreKey then
                return true
            end
        end
        return false
    end

    local function cleanupConfig(conf, def)
        local localStatus = false
        for k, v in pairs(conf) do
            if isIgnored(k) then
                return
            elseif def[k] == nil then
                conf[k] = nil
                localStatus = true
            elseif type(conf[k]) == "table" and type(def[k]) == "table" then
                localStatus = cleanupConfig(conf[k], def[k]) or localStatus
            end
        end
        return localStatus
    end

    local function applyDefaults(conf, def)
        local localStatus = false
        for k, v in pairs(def) do
            if isIgnored(k) then
                return
            elseif conf[k] == nil or reset then
                if type(v) == "table" then
                    conf[k] = {}
                    localStatus = applyDefaults(conf[k], v) or localStatus
                else
                    conf[k] = v
                    localStatus = true
                end
            elseif type(v) == "table" and type(conf[k]) == "table" then
                localStatus = applyDefaults(conf[k], v) or localStatus
            end
        end
        return localStatus
    end

    status = applyDefaults(config, defaults)
    status = cleanupConfig(config, defaults) or status
    return status
end

function asyncHttpRequest(method, url, args, resolve, reject)
    local request_thread = effil.thread(function (method, url, args)
        local requests = require 'requests'
        local result, response = pcall(requests.request, method, url, args)
        if result then
            response.json, response.xml = nil, nil
            return true, response
        else
            return false, response
        end
    end)(method, url, args)
    if not resolve then resolve = function() end end
    if not reject then reject = function() end end
    lua_thread.create(function()
        local runner = request_thread
        while true do
            local status, err = runner:status()
            if not err then
                if status == 'completed' then
                    local result, response = runner:get()
                    if result then
                        resolve(response)
                    else
                        reject(response)
                    end
                    return
                elseif status == 'canceled' then
                    return reject(status)
                end
            else
                return reject(err)
            end
            wait(0)
        end
    end)
end

function compareVersions(version1, version2)
    local function parseVersion(version)
        local major, minor, patch = version:match("(%d+)%.?(%d*)%.?(%d*)")
        return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
    end

    local major1, minor1, patch1 = parseVersion(version1)
    local major2, minor2, patch2 = parseVersion(version2)
    if major1 ~= major2 then return (major1 > major2) and 1 or -1 end
    if minor1 ~= minor2 then return (minor1 > minor2) and 1 or -1 end
    if patch1 ~= patch2 then return (patch1 > patch2) and 1 or -1 end
    return 0
end

function imgui.handleWindowDragging(pos, offset, size, menu)
    if not menu then return {x = pos.x, y = pos.y}, false end
    local mpos = imgui.GetMousePos()
    if mpos.x + offset.x >= pos.x and mpos.x <= pos.x + size.x - offset.x and mpos.y + offset.y >= pos.y and mpos.y <= pos.y + size.y - offset.y then
        if imgui.IsMouseClicked(0) then
            selectedbox = true
            tempOffset.x = mpos.x - pos.x
            tempOffset.y = mpos.y - pos.y
        end
    end
    if selectedbox then
        if imgui.IsMouseReleased(0) then
            selectedbox = false
        else
            return {x = mpos.x - tempOffset.x, y = mpos.y - tempOffset.y}, true
        end
    end
    return {x = pos.x, y = pos.y}, false
end

function convertColor(color, normalize, includeAlpha, hexColor)
    local r = bit.band(bit.rshift(color, 16), 0xFF)
    local g = bit.band(bit.rshift(color, 8), 0xFF)
    local b = bit.band(color, 0xFF)
    local a = bit.band(bit.rshift(color, 24), 0xFF)

    if normalize then
        r, g, b, a = r / 255, g / 255, b / 255, a / 255
    end

    if hexColor then
        if includeAlpha then
            return string.format("%02X%02X%02X%02X", a, r, g, b)
        else
            return string.format("%02X%02X%02X", r, g, b)
        end
    else
        if includeAlpha then
            return r, g, b, a
        else
            return r, g, b
        end
    end
end

function joinARGB(a, r, g, b, normalized)
    if normalized then
        a, r, g, b = math.floor(a * 255), math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
    end
    return bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b)
end

function imgui.TextColoredRGB(text)
    local style = imgui.GetStyle()
    local colors = style.Colors
    local col = imgui.Col

    local function designText(text__)
        local pos = imgui.GetCursorPos()
        if sampGetChatDisplayMode() == 2 then
            for i = 1, 1 --[[Shadow degree]] do
                imgui.SetCursorPos(imgui.ImVec2(pos.x + i, pos.y))
                imgui.TextColored(imgui.ImVec4(0, 0, 0, 1), text__) -- shadow
                imgui.SetCursorPos(imgui.ImVec2(pos.x - i, pos.y))
                imgui.TextColored(imgui.ImVec4(0, 0, 0, 1), text__) -- shadow
                imgui.SetCursorPos(imgui.ImVec2(pos.x, pos.y + i))
                imgui.TextColored(imgui.ImVec4(0, 0, 0, 1), text__) -- shadow
                imgui.SetCursorPos(imgui.ImVec2(pos.x, pos.y - i))
                imgui.TextColored(imgui.ImVec4(0, 0, 0, 1), text__) -- shadow
            end
        end
        imgui.SetCursorPos(pos)
    end

    -- Ensure color codes are in the form of {RRGGBBAA}
    text = text:gsub('{(%x%x%x%x%x%x)}', '{%1FF}')

    local color = colors[col.Text]
    local start = 1
    local a, b = text:find('{........}', start)

    while a do
        local t = text:sub(start, a - 1)
        if #t > 0 then
            designText(t)
            imgui.TextColored(color, t)
            imgui.SameLine(nil, 0)
        end

        local clr = text:sub(a + 1, b - 1)
        if clr:upper() == 'STANDART' then
            color = colors[col.Text]
        else
            clr = tonumber(clr, 16)
            if clr then
                local r = bit.band(bit.rshift(clr, 24), 0xFF)
                local g = bit.band(bit.rshift(clr, 16), 0xFF)
                local b = bit.band(bit.rshift(clr, 8), 0xFF)
                local a = bit.band(clr, 0xFF)
                color = imgui.ImVec4(r / 255, g / 255, b / 255, a / 255)
            end
        end

        start = b + 1
        a, b = text:find('{........}', start)
    end

    imgui.NewLine()
    if #text >= start then
        imgui.SameLine(nil, 0)
        designText(text:sub(start))
        imgui.TextColored(color, text:sub(start))
    end
end

function imgui.CustomButtonWithTooltip(name, color, colorHovered, colorActive, size, tooltip)
    local clr = imgui.Col
    imgui.PushStyleColor(clr.Button, color)
    imgui.PushStyleColor(clr.ButtonHovered, colorHovered)
    imgui.PushStyleColor(clr.ButtonActive, colorActive)
    if not size then size = imgui.ImVec2(0, 0) end
    local result = imgui.Button(name, size)
    imgui.PopStyleColor(3)
    if imgui.IsItemHovered() and tooltip then
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(8, 8))
        imgui.SetTooltip(tooltip)
        imgui.PopStyleVar()
    end
    return result
end

function imgui.CustomButton(name, color, colorHovered, colorActive, size)
    local clr = imgui.Col
    imgui.PushStyleColor(clr.Button, color)
    imgui.PushStyleColor(clr.ButtonHovered, colorHovered)
    imgui.PushStyleColor(clr.ButtonActive, colorActive)
    if not size then size = imgui.ImVec2(0, 0) end
    local result = imgui.Button(name, size)
    imgui.PopStyleColor(3)
    return result
end

function apply_custom_style()
    imgui.SwitchContext()
    local ImVec4 = imgui.ImVec4
    local ImVec2 = imgui.ImVec2
    local style = imgui.GetStyle()
    style.WindowRounding = 0
    style.WindowPadding = ImVec2(8, 8)
    style.WindowTitleAlign = ImVec2(0.5, 0.5)
    style.FrameRounding = 0
    style.ItemSpacing = ImVec2(8, 4)
    style.ScrollbarSize = 10
    style.ScrollbarRounding = 3
    style.GrabMinSize = 10
    style.GrabRounding = 0
    style.Alpha = 1
    style.FramePadding = ImVec2(4, 3)
    style.ItemInnerSpacing = ImVec2(4, 4)
    style.TouchExtraPadding = ImVec2(0, 0)
    style.IndentSpacing = 21
    style.ColumnsMinSpacing = 6
    style.ButtonTextAlign = ImVec2(0.5, 0.5)
    style.DisplayWindowPadding = ImVec2(22, 22)
    style.DisplaySafeAreaPadding = ImVec2(4, 4)
    style.AntiAliasedLines = true
    style.CurveTessellationTol = 1.25
    local colors = style.Colors
    local clr = imgui.Col
    colors[clr.FrameBg]                = ImVec4(0.48, 0.16, 0.16, 0.54)
    colors[clr.FrameBgHovered]         = ImVec4(0.98, 0.26, 0.26, 0.40)
    colors[clr.FrameBgActive]          = ImVec4(0.98, 0.26, 0.26, 0.67)
    colors[clr.TitleBg]                = ImVec4(0.04, 0.04, 0.04, 1.00)
    colors[clr.TitleBgActive]          = ImVec4(0.48, 0.16, 0.16, 1.00)
    colors[clr.TitleBgCollapsed]       = ImVec4(0.00, 0.00, 0.00, 0.51)
    colors[clr.CheckMark]              = ImVec4(0.98, 0.26, 0.26, 1.00)
    colors[clr.SliderGrab]             = ImVec4(0.88, 0.26, 0.24, 1.00)
    colors[clr.SliderGrabActive]       = ImVec4(0.98, 0.26, 0.26, 1.00)
    colors[clr.Button]                 = ImVec4(0.98, 0.26, 0.26, 0.40)
    colors[clr.ButtonHovered]          = ImVec4(0.98, 0.26, 0.26, 1.00)
    colors[clr.ButtonActive]           = ImVec4(0.98, 0.06, 0.06, 1.00)
    colors[clr.Header]                 = ImVec4(0.98, 0.26, 0.26, 0.31)
    colors[clr.HeaderHovered]          = ImVec4(0.98, 0.26, 0.26, 0.80)
    colors[clr.HeaderActive]           = ImVec4(0.98, 0.26, 0.26, 1.00)
    colors[clr.Separator]              = colors[clr.Border]
    colors[clr.SeparatorHovered]       = ImVec4(0.75, 0.10, 0.10, 0.78)
    colors[clr.SeparatorActive]        = ImVec4(0.75, 0.10, 0.10, 1.00)
    colors[clr.ResizeGrip]             = ImVec4(0.98, 0.26, 0.26, 0.25)
    colors[clr.ResizeGripHovered]      = ImVec4(0.98, 0.26, 0.26, 0.67)
    colors[clr.ResizeGripActive]       = ImVec4(0.98, 0.26, 0.26, 0.95)
    colors[clr.TextSelectedBg]         = ImVec4(0.98, 0.26, 0.26, 0.35)
    colors[clr.Text]                   = ImVec4(1.00, 1.00, 1.00, 1.00)
    colors[clr.TextDisabled]           = ImVec4(0.50, 0.50, 0.50, 1.00)
    colors[clr.WindowBg]               = ImVec4(0.06, 0.06, 0.06, 0.94)
    colors[clr.PopupBg]                = ImVec4(0.08, 0.08, 0.08, 0.94)
    colors[clr.Border]                 = ImVec4(0.43, 0.43, 0.50, 0.50)
    colors[clr.BorderShadow]           = ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[clr.MenuBarBg]              = ImVec4(0.14, 0.14, 0.14, 1.00)
    colors[clr.ScrollbarBg]            = ImVec4(0.02, 0.02, 0.02, 0.53)
    colors[clr.ScrollbarGrab]          = ImVec4(0.31, 0.31, 0.31, 1.00)
    colors[clr.ScrollbarGrabHovered]   = ImVec4(0.41, 0.41, 0.41, 1.00)
    colors[clr.ScrollbarGrabActive]    = ImVec4(0.51, 0.51, 0.51, 1.00)
    colors[clr.PlotLines]              = ImVec4(0.61, 0.61, 0.61, 1.00)
    colors[clr.PlotLinesHovered]       = ImVec4(1.00, 0.43, 0.35, 1.00)
    colors[clr.PlotHistogram]          = ImVec4(0.90, 0.70, 0.00, 1.00)
    colors[clr.PlotHistogramHovered]   = ImVec4(1.00, 0.60, 0.00, 1.00)
end
