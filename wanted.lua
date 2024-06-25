script_name("wanted")
script_author("akacross")
script_version("0.5.12")
script_url("https://akacross.net/")

local scriptPath = thisScript().path
local scriptName = thisScript().name
local scriptVersion = thisScript().version

-- Requirements
require 'lib.moonloader'
local ffi = require 'ffi'
local effil = require 'effil'
local lfs = require 'lfs'
local mem = require 'memory'
local wm = require 'lib.windows.message'
local imgui = require 'mimgui'
local encoding = require 'encoding'
local sampev = require 'lib.samp.events'
local weapons = require 'game.weapons'
local flag = require 'moonloader'.font_flag
local fa = require 'fAwesome6'
local requests = require 'requests'
local dlstatus = require 'moonloader'.download_status

-- Encoding
encoding.default = 'CP1251'
local u8 = encoding.UTF8

-- Paths
local workingDir = getWorkingDirectory()
local configDir = workingDir .. '\\config\\'
local cfgFile = configDir .. 'wanted.json'


local mainc = imgui.ImVec4(0.98, 0.26, 0.26, 1.00)
local new, str, sizeof = imgui.new, ffi.string, ffi.sizeof
local wanted = {}
local wanted_defaultSettings = {
	autosave = true,
	_enabled = true,
	timer = 5,
	windowpos = {500, 500}
}

local ped, h = playerPed, playerHandle

local menu = new.bool(false)
local wantedlist = nil
local _last_wanted = 0
local refresh = false
local windowdisable = false
local inuse_move = false 
local selectedbox = false
local size = {
	{x = 0, y = 0}
}
local offsetX = 0
local offsetY = 0

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

	sampRegisterChatCommand('wanted.settings', function()
		menu[0] = not menu[0]
	end)

	while true do wait(0)
		if sampGetGamestate() ~= 3 and wantedlist then wantedlist = nil end
		if wanted._enabled and wanted.timer <= localClock() - _last_wanted then
			sampSendChat("/wanted")
			_last_wanted = localClock()
		end
	end
end

function onScriptTerminate(scr, quitGame)
	if scr == script.this then
		if wanted.autosave then
			local success, err = saveConfig(cfgFile, wanted)
            if not success then
                print("Error saving config: " .. err)
            end
		end
	end
end

function onWindowMessage(msg, wparam, lparam)
	if wparam == VK_ESCAPE and menu[0] then
        if msg == wm.WM_KEYDOWN then
            consumeWindowMessage(true, false)
        end
        if msg == wm.WM_KEYUP then
            menu[0] = false
        end
    end
end

function sampev.onSendCommand(command)
	if string.find(command, '/wanted') then
		refresh = true
	end
end

function sampev.onServerMessage(color, text)
	if wanted._enabled then
		if text:match("You're not a Lawyer / Cop / FBI!") then
			wanted._enabled = false
			return false
		end

		if text:match("__________WANTED LIST__________") then return false end
		if text:match("________________________________") and string.len(text) == 32 then return false end

		if text:match("No current wanted suspects.") then
			wantedlist = nil
			return false
		end

		local nickname, playerid, charges = text:match("(.+) %((%d+)%): %{b4b4b4%}(%d+) outstanding charge[s]?%.")
		if nickname and playerid and charges then
			if not wantedlist or refresh then
				wantedlist = {}
				refresh = false
			end
			wantedlist[#wantedlist + 1] = {
				["PlayerName"] = nickname,
				["PlayerID"] = playerid,
				["Charges"] = charges
			}

			return false
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
		"POWER_OFF",
		"FLOPPY_DISK",
		"REPEAT",
		"ERASER",
		"RETWEET",
		"STAR"
	}
	for _, b in ipairs(list) do
		builder:AddText(fa(b))
	end
	defaultGlyphRanges1 = imgui.ImVector_ImWchar()
	builder:BuildRanges(defaultGlyphRanges1)
	imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(fa.get_font_data_base85("solid"), 14, config, defaultGlyphRanges1[0].Data)
	
	imgui.GetIO().IniFilename = nil
end)

imgui.OnFrame(function() return wanted._enabled and not isPauseMenuActive() and not sampIsScoreboardOpen() and sampGetChatDisplayMode() > 0 and not isKeyDown(VK_F10) end,
function()
	if menu[0] then
		local mpos = imgui.GetMousePos()
		if mpos.x >= wanted.windowpos[1] and
		mpos.x <= wanted.windowpos[1] + size.x and
		mpos.y >= wanted.windowpos[2] and
		mpos.y <= wanted.windowpos[2] + size.y then
			if imgui.IsMouseClicked(0) then
				selectedbox = true
				offsetX = mpos.x - wanted.windowpos[1]
				offsetY = mpos.y - wanted.windowpos[2]
			end
		end
		if selectedbox then
			if imgui.IsMouseReleased(0) then
				selectedbox = false
			else
				wanted.windowpos[1] = mpos.x - offsetX
				wanted.windowpos[2] = mpos.y - offsetY
			end
		end
	end
	imgui.SetNextWindowPos(imgui.ImVec2(wanted.windowpos[1], wanted.windowpos[2]), imgui.Cond.Always)
	imgui.Begin(script.this.name, nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.AlwaysAutoResize)
		if wantedlist then
			for _, v in pairs(wantedlist) do
				imgui.Text(string.format("%s(%s): %s outstanding charges.", v.PlayerName, v.PlayerID, v.Charges))
			end
		else
			imgui.Text("No current wanted suspects.")
		end
		size = imgui.GetWindowSize()
	imgui.End()
end).HideCursor = true

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

imgui.OnFrame(function() return menu[0] end,
function()
    local width, height = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
    imgui.Begin(string.format("%s %s Settings - Version: %s", fa.STAR, scriptName, scriptVersion), menu, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.AlwaysAutoResize)
        imgui.BeginChild("##1", imgui.ImVec2(95, 255), true)
        imgui.SetCursorPos(imgui.ImVec2(5, 5))

        if imgui.CustomButtonWithTooltip(
            fa.POWER_OFF..'##1',
            wanted._enabled and imgui.ImVec4(0.15, 0.59, 0.18, 0.7) or imgui.ImVec4(1, 0.19, 0.19, 0.5),
            wanted._enabled and imgui.ImVec4(0.15, 0.59, 0.18, 0.5) or imgui.ImVec4(1, 0.19, 0.19, 0.3),
            wanted._enabled and imgui.ImVec4(0.15, 0.59, 0.18, 0.4) or imgui.ImVec4(1, 0.19, 0.19, 0.2),
            imgui.ImVec2(90, 37.5),
            "Give damage toggle"
        ) then
            wanted._enabled = not wanted._enabled
        end

        imgui.SetCursorPos(imgui.ImVec2(5, 43.5))

        if imgui.CustomButtonWithTooltip(
            fa.FLOPPY_DISK,
            imgui.ImVec4(0.16, 0.16, 0.16, 0.9),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 0.5),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 1),
            imgui.ImVec2(90, 37.5),
            "Save the Script"
        ) then
            local success, err = saveConfig(cfgFile, wanted)
            if not success then
                print("Error saving config: " .. err)
            end
        end

        imgui.SetCursorPos(imgui.ImVec2(5, 82))

        if imgui.CustomButtonWithTooltip(
            fa.REPEAT,
            imgui.ImVec4(0.16, 0.16, 0.16, 0.9),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 0.5),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 1),
            imgui.ImVec2(90, 37.5),
            "Reload the Script"
        ) then
            loadIni()
        end

        imgui.SetCursorPos(imgui.ImVec2(5, 120.5))

        if imgui.CustomButtonWithTooltip(
            fa.ERASER,
            imgui.ImVec4(0.16, 0.16, 0.16, 0.9),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 0.5),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 1),
            imgui.ImVec2(90, 37.5),
            "Reset the Script to default settings"
        ) then
            blankIni()
        end

        imgui.SetCursorPos(imgui.ImVec2(5, 159))

        if imgui.CustomButtonWithTooltip(
            fa.RETWEET .. ' Update',
            imgui.ImVec4(0.16, 0.16, 0.16, 0.9),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 0.5),
            imgui.ImVec4(mainc.x, mainc.y, mainc.z, 1),
            imgui.ImVec2(90, 37.5),
            "Update the script"
        ) then
            ---
        end

        imgui.SetCursorPos(imgui.ImVec2(5, 203))

        if imgui.Checkbox('Autosave', new.bool(wanted.autosave)) then
            wanted.autosave = not wanted.autosave
        end

        imgui.SetCursorPos(imgui.ImVec2(5, 230))

        imgui.EndChild()

        imgui.SetCursorPos(imgui.ImVec2(100, 25))

        imgui.BeginChild("##3", imgui.ImVec2(135, 255), true)

        imgui.EndChild()
    imgui.PopStyleVar()
    imgui.End()
end)

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
