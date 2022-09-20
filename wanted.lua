script_name("Wanted")
script_author("akacross")
script_url("https://akacross.net/")

local script_version = 0.3
local script_version_text = '0.3'

require"lib.moonloader"
require"lib.sampfuncs"
require 'extensions-lite'

local imgui, ffi = require 'mimgui', require 'ffi'
local new, str, sizeof = imgui.new, ffi.string, ffi.sizeof
local sampev = require 'lib.samp.events'
local wm  = require 'lib.windows.message'
local vk = require 'vkeys'
local faicons = require 'fa-icons'
local ti = require 'tabler_icons'
local fa = require 'fAwesome5'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local path = getWorkingDirectory() .. '\\config\\' 
local cfg = path .. 'wanted.ini'
local script_path = thisScript().path
local script_url = "https://raw.githubusercontent.com/akacross/wanted/main/wanted.lua"
local update_url = "https://raw.githubusercontent.com/akacross/wanted/main/wanted.txt"

local blank = {}
local wanted = {
	autosave = true,
	autoupdate = true,
	_enabled = true,
	messages = false,
	timer = 5,
	windowpos = {500, 500}
}
local menu = new.bool(false)
local wantedlist = {}
local _last_wanted = 0
local refresh = false
local wanted_toggle = false
local windowdisable = false
local temp_pos = {x = 0, y = 0}
local move = false
local isgamepaused = false

local function loadIconicFont(fromfile, fontSize, min, max, fontdata)
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    local iconRanges = new.ImWchar[3](min, max, 0)
	if fromfile then
		imgui.GetIO().Fonts:AddFontFromFileTTF(fontdata, fontSize, config, iconRanges)
	else
		imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(fontdata, fontSize, config, iconRanges)
	end
end

imgui.OnInitialize(function()
	apply_custom_style()

	loadIconicFont(false, 14.0, faicons.min_range, faicons.max_range, faicons.get_font_data_base85())
	loadIconicFont(true, 14.0, fa.min_range, fa.max_range, 'moonloader/resource/fonts/fa-solid-900.ttf')
	loadIconicFont(false, 14.0, ti.min_range, ti.max_range, ti.get_font_data_base85())
	
	imgui.GetIO().ConfigWindowsMoveFromTitleBarOnly = true
	imgui.GetIO().IniFilename = nil
end)

imgui.OnFrame(function() return wanted._enabled and windowdisable and not isgamepaused end,
function()
	imgui.SetNextWindowPos(imgui.ImVec2(wanted.windowpos[1], wanted.windowpos[2]), imgui.Cond.Always)
	imgui.Begin(script.this.name, nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.AlwaysAutoResize)
		for key, value in pairs(wantedlist) do
			if table.contains(value, "No current wanted suspects.") then
				imgui.Text(value.Message)
			else
				imgui.Text(string.format("%s[%s]: %s outstanding charges.", value.PlayerName, value.PlayerID, value.Charges))
			end
		end
	imgui.End()
end).HideCursor = true

imgui.OnFrame(function() return menu[0] and not isgamepaused end,
function()
	local width, height = getScreenResolution()
	imgui.SetNextWindowPos(imgui.ImVec2(width / 2, height / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
	imgui.Begin(fa.ICON_FA_STAR .. string.format("%s Settings - Version: %s", script.this.name, script_version_text), menu, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.AlwaysAutoResize)

		imgui.BeginChild("##1", imgui.ImVec2(85, 392), true)
				
			imgui.SetCursorPos(imgui.ImVec2(5, 5))
      
			if imgui.CustomButton(
				faicons.ICON_POWER_OFF, 
				wanted._enabled and imgui.ImVec4(0.15, 0.59, 0.18, 0.7) or imgui.ImVec4(1, 0.19, 0.19, 0.5), 
				wanted._enabled and imgui.ImVec4(0.15, 0.59, 0.18, 0.5) or imgui.ImVec4(1, 0.19, 0.19, 0.3), 
				wanted._enabled and imgui.ImVec4(0.15, 0.59, 0.18, 0.4) or imgui.ImVec4(1, 0.19, 0.19, 0.2), 
				imgui.ImVec2(75, 75)) then
				wanted._enabled = not wanted._enabled
			end
			if imgui.IsItemHovered() then
				imgui.SetTooltip('Toggles Notifications')
			end
		
			imgui.SetCursorPos(imgui.ImVec2(5, 81))

			if imgui.CustomButton(
				faicons.ICON_FLOPPY_O,
				imgui.ImVec4(0.16, 0.16, 0.16, 0.9), 
				imgui.ImVec4(0.40, 0.12, 0.12, 1), 
				imgui.ImVec4(0.30, 0.08, 0.08, 1), 
				imgui.ImVec2(75, 75)) then
				saveIni()
			end
			if imgui.IsItemHovered() then
				imgui.SetTooltip('Save the Script')
			end
      
			imgui.SetCursorPos(imgui.ImVec2(5, 157))

			if imgui.CustomButton(
				faicons.ICON_REPEAT, 
				imgui.ImVec4(0.16, 0.16, 0.16, 0.9), 
				imgui.ImVec4(0.40, 0.12, 0.12, 1), 
				imgui.ImVec4(0.30, 0.08, 0.08, 1), 
				imgui.ImVec2(75, 75)) then
				loadIni()
			end
			if imgui.IsItemHovered() then
				imgui.SetTooltip('Reload the Script')
			end

			imgui.SetCursorPos(imgui.ImVec2(5, 233))

			if imgui.CustomButton(
				faicons.ICON_ERASER, 
				imgui.ImVec4(0.16, 0.16, 0.16, 0.9), 
				imgui.ImVec4(0.40, 0.12, 0.12, 1), 
				imgui.ImVec4(0.30, 0.08, 0.08, 1), 
				imgui.ImVec2(75, 75)) then
				blankIni()
			end
			if imgui.IsItemHovered() then
				imgui.SetTooltip('Reset the Script to default settings')
			end

			imgui.SetCursorPos(imgui.ImVec2(5, 309))

			if imgui.CustomButton(
				faicons.ICON_RETWEET .. ' Update',
				imgui.ImVec4(0.16, 0.16, 0.16, 0.9), 
				imgui.ImVec4(0.40, 0.12, 0.12, 1), 
				imgui.ImVec4(0.30, 0.08, 0.08, 1),  
				imgui.ImVec2(75, 75)) then
				update_script()
			end
			if imgui.IsItemHovered() then
				imgui.SetTooltip('Update the script')
			end
      
		imgui.EndChild()
		
		imgui.SetCursorPos(imgui.ImVec2(92, 28))

		imgui.BeginChild("##2", imgui.ImVec2(337, 100), true)
      
			imgui.SetCursorPos(imgui.ImVec2(5,5))
			if imgui.CustomButton(fa.ICON_FA_COG .. '  Settings',
				imgui.ImVec4(0.56, 0.16, 0.16, 1),
				imgui.ImVec4(0.40, 0.12, 0.12, 1), 
				imgui.ImVec4(0.30, 0.08, 0.08, 1), 
				imgui.ImVec2(165, 75)) then
			end
		imgui.EndChild()

		imgui.SetCursorPos(imgui.ImVec2(92, 112))
		
		imgui.BeginChild("##3", imgui.ImVec2(337, 276), true)
		
			if imgui.Checkbox('Wanted Messages', new.bool(wanted.messages)) then 
				wanted.messages = not wanted.messages
			end
		
		imgui.EndChild()
		imgui.SetCursorPos(imgui.ImVec2(92, 384))
		
		imgui.BeginChild("##5", imgui.ImVec2(337, 36), true)
			if imgui.Checkbox('Autosave', new.bool(wanted.autosave)) then 
				wanted.autosave = not wanted.autosave 
				saveIni() 
			end
			imgui.SameLine()
			if imgui.Button(move and u8"Undo##1" or u8"Move##1") then
				move = not move
				if move then
					sampAddChatMessage(string.format('%s: Press {FF0000}%s {FFFFFF}to save the pos.', script.this.name, vk.id_to_name(VK_LBUTTON)), -1) 
					temp_pos.x = wanted.windowpos[1]
					temp_pos.y = wanted.windowpos[2]
					move = true
				else
					wanted.windowpos[1] = temp_pos.x
					wanted.windowpos[2] = temp_pos.y
					move = false
				end
			end
		imgui.EndChild()
	imgui.End()
end)

function main()
	blank = table.deepcopy(wanted)
	if not doesDirectoryExist(path) then createDirectory(path) end
	if doesFileExist(cfg) then loadIni() else blankIni() end
	wanted = table.assocMerge(blank, wanted)
	while not isSampAvailable() do wait(100) end
	sampAddChatMessage("["..script.this.name..'] '.. "{FF1A74}(/wanted.settings) Authors: " .. table.concat(thisScript().authors, ", "), -1)
	sampRegisterChatCommand('wanted.settings', function()
		menu[0] = not menu[0]
	end)
	
	while true do wait(0)
		if update then
			lua_thread.create(function() 
				menu[0] = false
				wanted.autosave = false
				os.remove(cfg)
				wait(20000) 
				thisScript():reload()
				update = false
			end)
		end
		
		if table.contains_key(wantedlist, 1) then
			windowdisable = true
		else
			windowdisable = false
		end
	
		if move then	
			x, y = getCursorPos()
			if isKeyJustPressed(VK_LBUTTON) then 
				move = false
			elseif isKeyJustPressed(VK_ESCAPE) then
				move = false
			else 
				wanted.windowpos[1] = x + 1
				wanted.windowpos[2] = y + 1
			end
		end
		
		if wanted._enabled and wanted.timer <= localClock() - _last_wanted and not isgamepaused then
			wanted_toggle = true
			sampSendChat("/wanted")
			_last_wanted = localClock()
		end
	end	
end

function onScriptTerminate(scr, quitGame) 
	if scr == script.this then 
		if wanted.autosave then 
			saveIni() 
		end 
	end
end

function onWindowMessage(msg, wparam, lparam)
	if msg == wm.WM_KILLFOCUS then
		isgamepaused = true
	elseif msg == wm.WM_SETFOCUS then
		isgamepaused = false
	end

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

	if text:find("__________WANTED LIST__________") and wanted._enabled then
		if not wanted_toggle and wanted.messages then
			message(text, color)
		end
		return false
	end
	
	if text:find("outstanding charges.") and wanted._enabled then
		if refresh then
			wantedlist = {}
			refresh = false
		end
		
		local nickname, playerid, charges = text:match("(.+) %((.+)%): %{b4b4b4%}(.+) outstanding charges.")
		wantedlist[#wantedlist + 1] = {
			["PlayerName"] = nickname,
			["PlayerID"] = playerid,
			["Charges"] = charges
		}
		
		if not wanted_toggle and wanted.messages then
			message(text, color)
		end
		
		return false
	end
	
	if text:find("No current wanted suspects.") and wanted._enabled then
		if refresh then
			wantedlist = {}
			refresh = false
		end
		
		wantedlist[#wantedlist + 1] = {
			["Message"] = text
		}
		if not wanted_toggle and wanted.messages then
			message(text, color)
		end
		return false
	end
	
	if text:find("________________________________") and string.len(text) == 32 and wanted._enabled then
		if not wanted_toggle and wanted.messages then
			message(text, color)
		end
		wanted_toggle = false
		return false
	end
	
	if text:find("You're not a Lawyer / Cop / FBI!") and wanted._enabled then
		return false
	end
end

function message(text, color)
	local g, b, _, r = hex2rgba_int(color)
	local rgb = {r, g, b}
	sampAddChatMessage(text, '0x'..colorRgbToHex(rgb))
end

function blankIni()
	wanted = table.deepcopy(blank)
	saveIni()
	loadIni()
end

function loadIni()
	local f = io.open(cfg, "r")
	if f then
		wanted = decodeJson(f:read("*all"))
		f:close()
	end
end

function saveIni()
	if type(wanted) == "table" then
		local f = io.open(cfg, "w")
		f:close()
		if f then
			f = io.open(cfg, "r+")
			f:write(encodeJson(wanted))
			f:close()
		end
	end
end

function update_script()
	downloadUrlToFile(update_url, getWorkingDirectory()..'/'..string.lower(script.this.name)..'.txt', function(id, status)
		if status == dlstatus.STATUS_ENDDOWNLOADDATA then
			update_text = https.request(update_url)
			update_version = update_text:match("version: (.+)")
			
			--local split1 = split(script_path, 'moonloader\\')
			--local split2 = split(split1[2], ".")
			--if split2[2] ~= nil then
				--if split2[2] ~= 'lua' then
					if tonumber(update_version) > script_version then
						sampAddChatMessage(string.format("{ABB2B9}[%s]{FFFFFF} New version found! The update is in progress..", script.this.name), -1)
						downloadUrlToFile(script_url, script_path, function(id, status)
							if status == dlstatus.STATUS_ENDDOWNLOADDATA then
								sampAddChatMessage(string.format("{ABB2B9}[%s]{FFFFFF} The update was successful!", script.this.name), -1)
								update = true
							end
						end)
					end
				--end
			--end
		end
	end)
end

function table.contains_key(table, element)
	for key, _ in ipairs(table) do
		if key == element then
			return true
		end
	end
	return false
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

function hex2rgba(rgba)
	local a = bit.band(bit.rshift(rgba, 24),	0xFF)
	local r = bit.band(bit.rshift(rgba, 16),	0xFF)
	local g = bit.band(bit.rshift(rgba, 8),		0xFF)
	local b = bit.band(rgba, 0xFF)
	return r / 255, g / 255, b / 255, a / 255
end

function hex2rgba_int(rgba)
	local a = bit.band(bit.rshift(rgba, 24),	0xFF)
	local r = bit.band(bit.rshift(rgba, 16),	0xFF)
	local g = bit.band(bit.rshift(rgba, 8),		0xFF)
	local b = bit.band(rgba, 0xFF)
	return r, g, b, a
end

function hex2rgb(rgba)
	local a = bit.band(bit.rshift(rgba, 24),	0xFF)
	local r = bit.band(bit.rshift(rgba, 16),	0xFF)
	local g = bit.band(bit.rshift(rgba, 8),		0xFF)
	local b = bit.band(rgba, 0xFF)
	return r / 255, g / 255, b / 255
end

function hex2rgb_int(rgba)
	local a = bit.band(bit.rshift(rgba, 24),	0xFF)
	local r = bit.band(bit.rshift(rgba, 16),	0xFF)
	local g = bit.band(bit.rshift(rgba, 8),		0xFF)
	local b = bit.band(rgba, 0xFF)
	return r, g, b
end

function argb2hex(a, r, g, b)
	local argb = b
	argb = bit.bor(argb, bit.lshift(g, 8))
	argb = bit.bor(argb, bit.lshift(r, 16))
	argb = bit.bor(argb, bit.lshift(a, 24))
	return argb
end

function colorRgbToHex(rgb)
	local hexadecimal = ''
	for key, value in pairs(rgb) do
		local hex = ''
		while (value > 0) do
			local index = math.fmod(value, 16) + 1
			value = math.floor(value / 16)
			hex = string.sub('0123456789ABCDEF', index, index) .. hex
		end
		if(string.len(hex) == 0)then
			hex = '00'
		elseif(string.len(hex) == 1)then
			hex = '0' .. hex
		end
		hexadecimal = hexadecimal .. hex
	end
	return hexadecimal
end

function apply_custom_style()
	imgui.SwitchContext()
	local ImVec4 = imgui.ImVec4
	local ImVec2 = imgui.ImVec2
	local style = imgui.GetStyle()
	style.WindowRounding = 0
	style.WindowPadding = ImVec2(8, 8)
	style.WindowTitleAlign = ImVec2(0.5, 0.5)
	--style.ChildWindowRounding = 0
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
	--style.AntiAliasedShapes = true
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
	--colors[clr.ChildWindowBg]          = ImVec4(1.00, 1.00, 1.00, 0.00)
	colors[clr.PopupBg]                = ImVec4(0.08, 0.08, 0.08, 0.94)
	--colors[clr.ComboBg]                = colors[clr.PopupBg]
	colors[clr.Border]                 = ImVec4(0.43, 0.43, 0.50, 0.50)
	colors[clr.BorderShadow]           = ImVec4(0.00, 0.00, 0.00, 0.00)
	colors[clr.MenuBarBg]              = ImVec4(0.14, 0.14, 0.14, 1.00)
	colors[clr.ScrollbarBg]            = ImVec4(0.02, 0.02, 0.02, 0.53)
	colors[clr.ScrollbarGrab]          = ImVec4(0.31, 0.31, 0.31, 1.00)
	colors[clr.ScrollbarGrabHovered]   = ImVec4(0.41, 0.41, 0.41, 1.00)
	colors[clr.ScrollbarGrabActive]    = ImVec4(0.51, 0.51, 0.51, 1.00)
	--colors[clr.CloseButton]            = ImVec4(0.41, 0.41, 0.41, 0.50)
	--colors[clr.CloseButtonHovered]     = ImVec4(0.98, 0.39, 0.36, 1.00)
	--colors[clr.CloseButtonActive]      = ImVec4(0.98, 0.39, 0.36, 1.00)
	colors[clr.PlotLines]              = ImVec4(0.61, 0.61, 0.61, 1.00)
	colors[clr.PlotLinesHovered]       = ImVec4(1.00, 0.43, 0.35, 1.00)
	colors[clr.PlotHistogram]          = ImVec4(0.90, 0.70, 0.00, 1.00)
	colors[clr.PlotHistogramHovered]   = ImVec4(1.00, 0.60, 0.00, 1.00)
	--colors[clr.ModalWindowDarkening]   = ImVec4(0.80, 0.80, 0.80, 0.35)
end