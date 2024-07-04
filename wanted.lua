script_name("wanted")
script_author("akacross")
script_version("0.5.35")
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
    updateInProgress = false,
    lastVersion = "Unknown",
    Window = {
        Pos = {x = 500, y = 500},
        BackgroundColor = -16777216,
        BorderColor = -1,
        BorderSize = 2.0,
        Pivot = {x = 0.5, y = 0.0},
        Padding = {x = 8.0, y = 8.0}
    },
    Settings = {
        Enabled = true,
        Stars = false,
        ShowRefresh = false,
        Timer = 5,
        AutoCheckUpdate = true,
        AutoSave = true,
    }
}

local ped, h = playerPed, playerHandle
local wantedlist = nil
local last_wanted = 0
local commandSent = false
local isLoadingInterior = false

local new, str, sizeof = imgui.new, ffi.string, ffi.sizeof
local menu = {
    wanted = new.bool(false),
    settings = new.bool(false),
    confirm = new.bool(false)
}
local mainc = imgui.ImVec4(0.98, 0.26, 0.26, 1.00)
local bgColorEditing = false
local borderColorEditing = false
local windowSize = {x = 0, y = 0}
local tempOffset = {x = 0, y = 0}
local selectedbox = false
local confirmData = {['update'] = {status = false}}
local pivots = {
    {name = "Top-Left", value = {x = 0.0, y = 0.0}, icon = fa.ARROW_UP_LEFT},
    {name = "Top-Center", value = {x = 0.5, y = 0.0}, icon = fa.ARROW_UP},
    {name = "Top-Right", value = {x = 1.0, y = 0.0}, icon = fa.ARROW_UP_RIGHT},
    {name = "Center-Left", value = {x = 0.0, y = 0.5}, icon = fa.ARROW_LEFT},
    {name = "Center", value = {x = 0.5, y = 0.5}, icon = fa.SQUARE},
    {name = "Center-Right", value = {x = 1.0, y = 0.5}, icon = fa.ARROW_RIGHT},
    {name = "Bottom-Left", value = {x = 0.0, y = 1.0}, icon = fa.ARROW_DOWN_LEFT},
    {name = "Bottom-Center", value = {x = 0.5, y = 1.0}, icon = fa.ARROW_DOWN},
    {name = "Bottom-Right", value = {x = 1.0, y = 1.0}, icon = fa.ARROW_DOWN_RIGHT}
}

local function handleUpdate()
    if wanted.updateInProgress then
        formattedAddChatMessage(string.format("You have successfully upgraded from Version: %s to %s", wanted.lastVersion, scriptVersion), -1)
        wanted.updateInProgress = false
        saveConfigWithErrorHandling(cfgFile, wanted)
    end
    if wanted.Settings.AutoCheckUpdate then 
        checkForUpdate() 
    end
end

local function registerChatCommands()
    local function wantedMenu()
        if wanted.updateInProgress then
            formattedAddChatMessage("Update in progress. Please wait a moment.", -1)
            return
        end
        menu.settings[0] = not menu.settings[0]
    end

    sampRegisterChatCommand('wanted.settings', wantedMenu)
    sampRegisterChatCommand('ws', wantedMenu)
    sampRegisterChatCommand('wanted', function()
        if not wanted.Settings.Enabled then sampSendChat("/wanted") return end
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
end

function main()
    createDirectory(configDir)
    wanted = handleConfigFile(cfgFile, wanted_defaultSettings, wanted)

    wanted.Settings.AutoCheckUpdate = true

    repeat wait(0) until isSampAvailable()
    handleUpdate()
    registerChatCommands()

    while true do wait(0)
        if sampGetGamestate() ~= 3 and wantedlist then 
            if menu.wanted[0] then menu.wanted[0] = false end
            wantedlist = nil 
        end
        if wanted.Settings.Enabled and not isLoadingInterior and wanted.Settings.Timer <= localClock() - last_wanted then
            sampSendChat("/wanted")
            commandSent = true
            last_wanted = localClock()
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

function onScriptTerminate(scr, quitGame)
    if scr == script.this then
        if wanted.Settings.AutoSave then
            saveConfigWithErrorHandling(cfgFile, wanted)
        end
    end
end

function sampev.onShowTextDraw(id, data)
    if data.text:match("~r~Objects loading...") then
        isLoadingInterior = true
    end

    if data.text:match("~g~Objects loaded!") then
        isLoadingInterior = false
    end
end

function sampev.onServerMessage(color, text)
    if wanted.Settings.Enabled or commandSent then
        if text:match("You're not a Lawyer / Cop / FBI!") and color == -1347440726 then
            wanted.Settings.Enabled = false
        end

        local nickname = text:match("HQ: (.+) has been processed, was arrested.")
        if nickname and wantedlist and color == 641859242 then
            for k, v in pairs(wantedlist) do
                if v.name:match(nickname) then
                    table.remove(wantedlist, k)
                    break
                end
            end
        end

        if color == -8388353 then
            if text:match("__________WANTED LIST__________") then
                if not menu.wanted[0] then 
                    menu.wanted[0] = true 
                end
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
            wanted.Settings.Enabled = true
        end
    end
end

function loadFontAwesome6Icons(iconList, fontSize)
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    config.GlyphMinAdvanceX = 14
    local builder = imgui.ImFontGlyphRangesBuilder()
    
    for _, icon in ipairs(iconList) do
        builder:AddText(fa(icon))
    end
    
    local glyphRanges = imgui.ImVector_ImWchar()
    builder:BuildRanges(glyphRanges)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(fa.get_font_data_base85("solid"), fontSize, config, glyphRanges[0].Data)
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    local smallIcons = {"ARROWS_ROTATE", "CHECK"}
    local defaultIcons = {
        "STAR", "POWER_OFF", "FLOPPY_DISK", "REPEAT", "ERASER", "RETWEET",
        "CIRCLE_CHECK", "CIRCLE_XMARK", "ARROW_UP_LEFT", "ARROW_UP",
        "ARROW_UP_RIGHT", "ARROW_LEFT", "SQUARE", "ARROW_RIGHT",
        "ARROW_DOWN_LEFT", "ARROW_DOWN", "ARROW_DOWN_RIGHT"
    }
    loadFontAwesome6Icons(smallIcons, 8)
    loadFontAwesome6Icons(defaultIcons, 12)
    apply_custom_style()
end)

imgui.OnFrame(function()
    return menu.wanted[0] and wanted.Settings.Enabled and not isPauseMenuActive() and not sampIsScoreboardOpen() and sampGetChatDisplayMode() > 0 and not isKeyDown(VK_F10)
end,
function()
    local textLines = {"No current wanted suspects."}
    if wantedlist then
        textLines = {}
        for _, entry in ipairs(wantedlist) do
            table.insert(textLines, formatWantedString(entry))
        end
    end
    windowSize = calculateWindowSize(textLines, wanted.Window.Padding)

    local newPos, status = imgui.handleWindowDragging(wanted.Window.Pos, windowSize, wanted.Window.Pivot)
    if status and menu.settings[0] then wanted.Window.Pos = newPos end
    imgui.SetNextWindowPos(wanted.Window.Pos, imgui.Cond.Always, wanted.Window.Pivot)
    imgui.SetNextWindowSize(windowSize, imgui.Cond.Always)

    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(convertColor(wanted.Window.BackgroundColor, true, true)))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(convertColor(wanted.Window.BorderColor, true, true)))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, wanted.Window.BorderSize)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, wanted.Window.Padding)

    if imgui.Begin(scriptName, menu.wanted, imgui.WindowFlags.NoDecoration) then
        local totalTextHeight = #textLines * imgui.GetTextLineHeightWithSpacing()
        local startY = (windowSize.y - totalTextHeight) / 2
        
        for i, text in ipairs(textLines) do
            local textSize = imgui.CalcTextSize(text)
            local iconPosX = wanted.Window.Padding.x + wanted.Window.BorderSize / 2
            local textPosY = startY + (i - 1) * imgui.GetTextLineHeightWithSpacing()
            
            imgui.SetCursorPos(imgui.ImVec2(iconPosX, textPosY))
            imgui.TextColoredRGB(text)
        end

        if wanted.Settings.ShowRefresh and (wanted.Settings.Timer - (localClock() - last_wanted)) >= wanted.Settings.Timer - 1 and (wanted.Settings.Timer - (localClock() - last_wanted)) <= 11 then
            local textSize = imgui.CalcTextSize(fa.CHECK)
            local iconPosX = windowSize.x - textSize.x - wanted.Window.BorderSize / 2
            local iconPosY = wanted.Window.BorderSize / 2

            imgui.SetCursorPos(imgui.ImVec2(iconPosX, iconPosY))
            imgui.TextColoredRGB('{00D900}' .. fa.CHECK)
        end
        imgui.PopStyleVar(2)
        imgui.PopStyleColor(2)
        imgui.End()
    end
end).HideCursor = true

imgui.OnFrame(function() return menu.settings[0] end,
function()
    local title = string.format("%s %s Settings - Version: %s", fa.STAR, firstToUpper(scriptName), scriptVersion)
    local io = imgui.GetIO()
    local center = imgui.ImVec2(io.DisplaySize.x / 2, io.DisplaySize.y / 2)
    imgui.SetNextWindowPos(center, imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
    imgui.Begin(title, menu.settings, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.AlwaysAutoResize)
        imgui.BeginChild("## Buttons", imgui.ImVec2(272, 41), true)
            imgui.SetCursorPos(imgui.ImVec2(0, 0))
            if imgui.CustomButtonWithTooltip(
                fa.POWER_OFF..'##1',
                wanted.Settings.Enabled and imgui.ImVec4(0.15, 0.59, 0.18, 0.7) or imgui.ImVec4(1, 0.19, 0.19, 0.5),
                wanted.Settings.Enabled and imgui.ImVec4(0.15, 0.59, 0.18, 0.5) or imgui.ImVec4(1, 0.19, 0.19, 0.3),
                wanted.Settings.Enabled and imgui.ImVec4(0.15, 0.59, 0.18, 0.4) or imgui.ImVec4(1, 0.19, 0.19, 0.2),
                imgui.ImVec2(50.0, 40.0),
                "Toggle Wanted Menu"
            ) then
                wanted.Settings.Enabled = not wanted.Settings.Enabled
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
                'Check for update'
            ) then
                checkForUpdate()
            end
        imgui.EndChild()

        imgui.SetCursorPos(imgui.ImVec2(5, 65))
        imgui.BeginChild("## Settings", imgui.ImVec2(268, 150), false)
            if imgui.Checkbox('Stars', new.bool(wanted.Settings.Stars)) then
                wanted.Settings.Stars = not wanted.Settings.Stars
            end
            imgui.SameLine()
            imgui.PushItemWidth(35)
            local padding = new.float[1](wanted.Window.Padding.x)
            if imgui.DragFloat('Padding', padding, 0.1, 1, 10, "%.1f") then
                wanted.Window.Padding = {x = padding[0], y = padding[0]}
            end
            imgui.PopItemWidth()
            
            if imgui.Checkbox('Show Refresh', new.bool(wanted.Settings.ShowRefresh)) then
                wanted.Settings.ShowRefresh = not wanted.Settings.ShowRefresh
            end
            imgui.SameLine()
            imgui.PushItemWidth(30)
            local timer = new.float[1](wanted.Settings.Timer)
            if imgui.DragFloat('Refresh Rate', timer, 1, 2, 10, "%.f") then
                wanted.Settings.Timer = timer[0]
            end
            imgui.PopItemWidth()
            
            local bgColor = new.float[4](convertColor(wanted.Window.BackgroundColor, true, true))
            local bgStatus = imgui.ColorEdit4('##bgColor', bgColor, imgui.ColorEditFlags.NoInputs + imgui.ColorEditFlags.NoLabel + imgui.ColorEditFlags.AlphaBar)
            if bgStatus then
                wanted.Window.BackgroundColor = joinARGB(bgColor[3], bgColor[0], bgColor[1], bgColor[2], true)
            end
            imgui.SameLine()
            imgui.Text('Background Color')
            
            local borderColor = new.float[4](convertColor(wanted.Window.BorderColor, true, true))
            local borderStatus = imgui.ColorEdit4('##borderColor', borderColor, imgui.ColorEditFlags.NoInputs + imgui.ColorEditFlags.NoLabel + imgui.ColorEditFlags.AlphaBar)
            if borderStatus then
                wanted.Window.BorderColor = joinARGB(borderColor[3], borderColor[0], borderColor[1], borderColor[2], true)
            end
            imgui.SameLine()
            imgui.Text('Border Color')
            imgui.SameLine()
            imgui.PushItemWidth(35)
            local border = new.float[1](wanted.Window.BorderSize)
            if imgui.DragFloat('Border Size', border, 0.1, 1, 5, "%.1f") then
                wanted.Window.BorderSize = border[0]
            end
            imgui.PopItemWidth()

            imgui.PushItemWidth(130)
            if imgui.BeginCombo("Select Pivot", findPivotIndex(wanted.Window.Pivot)) then
                for i = 1, #pivots do
                    local pivot = pivots[i]
                    if imgui.Selectable(pivot.name .. " " .. pivot.icon, comparePivots(wanted.Window.Pivot, pivot.value)) then
                        wanted.Window.Pivot = pivot.value
                    end
                end
                imgui.EndCombo()
            end
            imgui.PopItemWidth()

            if imgui.Checkbox('Auto-Update', new.bool(wanted.Settings.AutoCheckUpdate)) then
                wanted.Settings.AutoCheckUpdate = not wanted.Settings.AutoCheckUpdate
            end
            imgui.SameLine()
            if imgui.Checkbox('Auto-Save', new.bool(wanted.Settings.AutoSave)) then
                wanted.Settings.AutoSave = not wanted.Settings.AutoSave
            end

        imgui.EndChild()
    imgui.PopStyleVar()
    imgui.End()
end)

local function handleButton(label, action, width)
    width = width or 85
    if imgui.CustomButtonWithTooltip(label, imgui.ImVec4(0.16, 0.16, 0.16, 0.9), imgui.ImVec4(0.40, 0.12, 0.12, 1), imgui.ImVec4(0.30, 0.08, 0.08, 1), imgui.ImVec2(width, 45)) then
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
            print(compareVersions(scriptVersion, updateVersion))
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

function handleConfigFile(path, defaults, configVar, ignoreKeys)
    ignoreKeys = ignoreKeys or {}
    if doesFileExist(path) then
        local config, err = loadConfig(path)
        if not config then
            print("Error loading config from " .. path .. ": " .. err)

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

    -- Use metatable to handle default values
    setmetatable(config, {__index = function(t, k)
        if type(defaults[k]) == "table" then
            t[k] = {}
            applyDefaults(t[k], defaults[k])
            return t[k]
        end
    end})

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
        local parts = {}
        for part in version:gmatch("(%d+)") do
            table.insert(parts, tonumber(part))
        end
        return parts
    end

    local v1 = parseVersion(version1)
    local v2 = parseVersion(version2)

    local maxLength = math.max(#v1, #v2)
    for i = 1, maxLength do
        local part1 = v1[i] or 0
        local part2 = v2[i] or 0
        if part1 ~= part2 then
            return (part1 > part2) and 1 or -1
        end
    end
    return 0
end

function imgui.handleWindowDragging(pos, size, pivot)
    local mpos = imgui.GetMousePos()
    local offset = {x = size.x * pivot.x, y = size.y * pivot.y}
    local boxPos = {x = pos.x - offset.x, y = pos.y - offset.y}

    if mpos.x >= boxPos.x and mpos.x <= boxPos.x + size.x and mpos.y >= boxPos.y and mpos.y <= boxPos.y + size.y then
        if imgui.IsMouseClicked(0) and not imgui.IsAnyItemHovered() then
            selectedbox = true
            tempOffset = {x = mpos.x - boxPos.x, y = mpos.y - boxPos.y}
        end
    end
    if selectedbox then
        if imgui.IsMouseReleased(0) then
            selectedbox = false
        else
            if imgui.IsAnyItemHovered() then
				selectedbox = false
			else
                local newBoxPos = {x = mpos.x - tempOffset.x, y = mpos.y - tempOffset.y}
                return {x = newBoxPos.x + offset.x, y = newBoxPos.y + offset.y}, true
            end
        end
    end
    return {x = pos.x, y = pos.y}, false
end

function convertColor(color, normalize, includeAlpha, hexColor)
    if type(color) ~= "number" then
        error("Invalid color value. Expected a number.")
    end

    local r = bit.band(bit.rshift(color, 16), 0xFF)
    local g = bit.band(bit.rshift(color, 8), 0xFF)
    local b = bit.band(color, 0xFF)
    local a = includeAlpha and bit.band(bit.rshift(color, 24), 0xFF) or 255

    if normalize then
        r, g, b, a = r / 255, g / 255, b / 255, a / 255
    end

    if hexColor then
        return includeAlpha and string.format("%02X%02X%02X%02X", a, r, g, b) or string.format("%02X%02X%02X", r, g, b)
    else
        return includeAlpha and {r, g, b, a} or {r, g, b}
    end
end

function joinARGB(a, r, g, b, normalized)
    if normalized then
        a, r, g, b = math.floor(a * 255), math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
    end

    local function clamp(value)
        return math.max(0, math.min(255, value))
    end

    return bit.bor(bit.lshift(clamp(a), 24), bit.lshift(clamp(r), 16), bit.lshift(clamp(g), 8), clamp(b))
end

function comparePivots(pivot1, pivot2)
    return pivot1.x == pivot2.x and pivot1.y == pivot2.y
end

function findPivotIndex(pivot)
    for i, p in ipairs(pivots) do
        if comparePivots(p.value, pivot) then
            return p.name .. " " .. p.icon
        end
    end
    return "Unknown"
end

function formattedAddChatMessage(string, color)
    sampAddChatMessage(string.format("{ABB2B9}[%s]{FFFFFF} %s", firstToUpper(scriptName), string), color)
end

function firstToUpper(string)
    return (string:gsub("^%l", string.upper))
end

function saveConfigWithErrorHandling(path, config)
    local success, err = saveConfig(path, config)
    if not success then
        print("Error saving config to " .. path .. ": " .. err)
    end
    return success
end

function removeHexBrackets(text)
    return string.gsub(text, "{%x+}", "")
end

function calculateWindowSize(lines, padding)
    local totalHeight = 0
    local maxWidth = 0
    local lineSpacing = imgui.GetTextLineHeightWithSpacing() - imgui.GetTextLineHeight()

    for _, text in ipairs(lines) do
        local processedText = removeHexBrackets(text)
        local textSize = imgui.CalcTextSize(processedText)
        totalHeight = totalHeight + textSize.y + lineSpacing
        if textSize.x > maxWidth then
            maxWidth = textSize.x
        end
    end
    totalHeight = totalHeight - lineSpacing

    -- Calculate window size with effective padding
    local windowSize = imgui.ImVec2(
        maxWidth + padding.x * 2,
        totalHeight + padding.y * 2
    )
    return windowSize, effectivePadding
end

function formatWantedString(entry)
    return string.format(
        "%s (%d): {%s}%s",
        entry.name,
        entry.id,
        entry.charges == 6 and "FF0000FF" or "B4B4B4",
        wanted.Settings.Stars and string.rep(fa.STAR, entry.charges) or string.format("%d outstanding %s.", entry.charges, entry.charges == 1 and "charge" or "charges")
    )
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
