--[[ Shigaku Menu v9: Auto Spin + Codes
  Stop rules:
   FightStyle : Exotic / Halloween cosmetic / shiny (optionally Legendary), but NOT Ogre when "Skip Ogre" is on
   Height     : >= min height   (+ optional "undo lower rolls": keeps the tallest, takes back anything shorter)
   Ethnicity  : only the 3 tallest ethnicities (fixed list, both genders)
   HairColor  : Mythic only (white hair)
   Eyes       : rare eyes or heterochromia
   Gear       : Epic / Legendary / Mythic accessory on any slot
  A heavenly sound plays on every hit (sgk_heaven.mp3 in Real's workspace folder).
]]

local prev = getgenv().SGK_Menu
if prev then pcall(function() prev.Dead = true; prev.Spin = false end) end
if getgenv().SGK_Gui then pcall(function() getgenv().SGK_Gui:Destroy() end) end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UIS = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local SoundService = game:GetService("SoundService")
local LP = Players.LocalPlayer
local Client = LP:WaitForChild("PlayerScripts"):WaitForChild("Client")

pcall(function() local o = SoundService:FindFirstChild("SGK_Heaven"); if o then o:Destroy() end end)

local Character = require(Client:WaitForChild("Character"))
local Data = require(Client:WaitForChild("Data"))
local A = require(RS.Shared.Modules.Shared.Appearance)
local R = A.Registry
local HS = require(RS.Shared.Combat.HalloweenStyles)
local BridgeNet2 = require(RS.Packages.BridgeNet2)
local GS = require(RS.Shared.Modules.Global.Libraries.Game_Settings)
if not Data.IsReady() then Data.Await() end

local CODES = {
    "GiveMePity", "TenToes", "OurApolocheese", "FIXINGBUGS", "NEWCAMPUS",
    "WillShigakuGetScarier", "IsThisSchoolUpToCode?", "IsThisReallyTheUpdate",
    "HowScaryIsTheTwentyFourth", "TwentyFourthScare", "HALLOWEEN2026",
    "lapeace", "JUSTTHESTART", "bugfixes", "RELEASETHANKYOU",
}
local ALL_FIELDS = {"FightStyle", "Height", "Ethnicity", "HairColor", "Eyes", "Gear", "Mouth", "Ringtone"}
local GEAR_POINTS = {"Head", "Face", "Neck", "Jacket", "Back", "LeftArm", "RightArm", "Waist"}
local GEAR_HIT = {Epic = true, Legendary = true, Mythic = true}
local TALL_ETH = {dinka = true, dutch = true, maasai = true} -- only these count as an ethnicity hit
local SFX_FILE, SFX_B64 = "sgk_heaven.mp3", "sgk_heaven.b64"

local S = {
    Dead = false,
    Spin = false,
    StopOnHit = true,
    LegendaryStyle = false,
    RollOver = true,
    AutoCodes = false,
    HeightUndo = true,
    SkipOgre = true,
    Sfx = true,
    SfxVolume = 2,
    MinHeight = 78,
    Fields = {FightStyle = true, Height = false, Ethnicity = false, HairColor = false, Eyes = false, Gear = false, Mouth = false, Ringtone = false},
    Blocked = {},
    Announced = {},
    Rolls = 0,
    Undos = 0,
    Status = "Idle",
}
if prev then -- carry settings over
    if type(prev.Fields) == "table" then
        for k, v in pairs(prev.Fields) do
            local key = (k == "Hair") and "HairColor" or k
            if S.Fields[key] ~= nil then S.Fields[key] = v end
        end
    end
    for _, k in ipairs({"StopOnHit", "LegendaryStyle", "AutoCodes", "MinHeight", "HeightUndo", "SkipOgre", "Sfx", "SfxVolume"}) do if prev[k] ~= nil then S[k] = prev[k] end end
    if prev.RollOver ~= nil then S.RollOver = prev.RollOver end
end
getgenv().SGK_Menu = S

local function notify(title, text)
    pcall(function() StarterGui:SetCore("SendNotification", {Title = title, Text = text, Duration = 10}) end)
end
local function ftin(i) return ("%d'%d\""):format(math.floor(i / 12), i % 12) end

---------------------------------------------------------------- heavenly sound
local sfxSound
local function ensureSfx()
    if sfxSound and sfxSound.Parent then return true end
    local ok = pcall(function()
        if not isfile(SFX_FILE) then
            local raw = readfile(SFX_B64):gsub("%s", "")
            local dec = (crypt and crypt.base64decode) or base64decode or base64_decode
            writefile(SFX_FILE, dec(raw))
        end
        local s = Instance.new("Sound")
        s.Name = "SGK_Heaven"
        s.SoundId = getcustomasset(SFX_FILE)
        s.Volume = S.SfxVolume
        s.Parent = SoundService
        sfxSound = s
    end)
    return ok and sfxSound ~= nil
end
local function playSfx(force)
    if not (S.Sfx or force) then return end
    if ensureSfx() then
        pcall(function()
            sfxSound.Volume = S.SfxVolume
            sfxSound.TimePosition = 0
            sfxSound:Play()
        end)
    end
end

---------------------------------------------------------------- game logic
local function styleInfo() return Data.Get({"Style"}), Data.Get({"StyleShiny"}) == true end

-- a plain (non-shiny) Ogre style is filtered out when SkipOgre is on
local function isSkippedOgre()
    if not S.SkipOgre then return false end
    local style, shiny = styleInfo()
    return type(style) == "string" and style:lower():find("ogre", 1, true) ~= nil and not shiny
end

local function ethAvg(eth, gender)
    local ok, v = pcall(A.Height.Average, eth, gender)
    return ok and tonumber(v) or nil
end

local function curHeight()
    local c = Character.GetActive()
    return typeof(c) == "table" and tonumber(c.Height) or nil
end

local function sameColor(c, t)
    return typeof(c) == "table" and tonumber(c[1]) == t[1] and tonumber(c[2]) == t[2] and tonumber(c[3]) == t[3]
end
local function hairIsMythic(char)
    for _, w in ipairs(R.WhiteHair) do
        if sameColor(char.HairColor, w) then return true end
    end
    return false
end

local function gearTier(char, point)
    local acc = char.Accessories
    local id = tonumber(typeof(acc) == "table" and acc[point] or 0) or 0
    local ok, tier = pcall(R.accessoryRarity, point, id)
    return ok and tier or "None", id
end

local function isHit(field)
    local char = Character.GetActive()
    if typeof(char) ~= "table" then return false end
    if field == "FightStyle" then
        if isSkippedOgre() then return false end
        local style, shiny = styleInfo()
        local ok, rarity = pcall(A.StyleRarity, style, shiny)
        if ok and rarity == "Exotic" then return true end
        if ok and S.LegendaryStyle and rarity == "Legendary" then return true end
        local okC, cos = pcall(HS.Cosmetic, style, shiny)
        if okC and cos ~= nil then return true end
        return shiny
    elseif field == "Height" then
        return (tonumber(char.Height) or 0) >= S.MinHeight
    elseif field == "Ethnicity" then
        return TALL_ETH[char.Ethnicity] == true
    elseif field == "HairColor" then
        return hairIsMythic(char)
    elseif field == "Eyes" then
        return (tonumber(char.EyesRareLeft) or 0) > 0 or (tonumber(char.EyesRareRight) or 0) > 0
            or (typeof(char.Eyes) == "table" and char.Eyes.Heterochromia == true)
    elseif R.isAccessoryPoint(field) then
        return GEAR_HIT[(gearTier(char, field))] == true
    end
    local ok, rare = pcall(A.holdsRare, char, field)
    return ok and rare == true
end

local function describe(field)
    local char = Character.GetActive() or {}
    if field == "FightStyle" then
        local st, sh = styleInfo()
        local okR, rar = pcall(A.StyleRarity, st, sh)
        return tostring(st) .. (sh and " Shiny" or "") .. (okR and (" [" .. tostring(rar) .. "]") or "")
    elseif field == "Height" then return ftin(tonumber(char.Height) or 0)
    elseif field == "Ethnicity" then
        local a = ethAvg(char.Ethnicity, char.Gender)
        return tostring(char.Ethnicity) .. (a and (" (avg " .. ftin(a) .. ")") or "")
    elseif field == "HairColor" then
        return hairIsMythic(char) and "Mythic (white)" or table.concat(char.HairColor or {}, ",")
    elseif field == "Eyes" then
        return (typeof(char.Eyes) == "table" and char.Eyes.Heterochromia) and "Heterochromia" or "Rare eyes"
    elseif R.isAccessoryPoint(field) then
        local tier, id = gearTier(char, field)
        return ("%s #%s [%s]"):format(field, tostring(id), tostring(tier))
    elseif field == "Ringtone" then return tostring(char.Ringtone) end
    return "new " .. field
end

-- does the game currently protect this field's value (so a plain reroll would be refused)?
local function needsConfirm(field)
    if field == "FightStyle" then
        local st, sh = styleInfo()
        local ok, r = pcall(A.styleHoldsRare, st, sh)
        return ok and r == true
    elseif field == "Height" then
        return false
    end
    local char = Character.GetActive()
    if typeof(char) ~= "table" then return false end
    local ok, r = pcall(A.holdsRare, char, field)
    return ok and r == true
end

local rejected
local rejConn = Character.OnRejected(function(action, reason) rejected = reason or action end)

local function rollOnce(field, confirm)
    local before = Character.GetRerolls()
    rejected = nil
    if field == "FightStyle" then Character.RerollFightStyle(confirm == true)
    else Character.RerollField(Character.GetActiveIndex(), field, confirm == true) end
    local t = os.clock()
    while not S.Dead and os.clock() - t < 3 do
        if rejected then return false, tostring(rejected) end
        if Character.GetRerolls() < before then break end
        task.wait()
    end
    task.wait(0.04)
    return true
end

-- take back the last roll (the game's own Undo) and confirm the height is back to `target`
local function undoTo(target)
    rejected = nil
    Character.RollbackRoll()
    local t = os.clock()
    while not S.Dead and os.clock() - t < 3 do
        if rejected then return false, tostring(rejected) end
        if curHeight() == target then return true end
        task.wait()
    end
    return false, "timeout"
end

local refreshAll = function() end

local function activeRollFields()
    local fields = {}
    for _, f in ipairs(ALL_FIELDS) do
        if S.Fields[f] then
            if f == "Gear" then
                for _, p in ipairs(GEAR_POINTS) do
                    if not S.Blocked[p] then fields[#fields + 1] = p end
                end
            elseif not S.Blocked[f] then
                fields[#fields + 1] = f
            end
        end
    end
    return fields
end

task.spawn(function()
    local idx, fails = 0, 0
    while not S.Dead do
        if not S.Spin then
            task.wait(0.1)
        else
            local fields = activeRollFields()

            local stop = false
            local open = {}
            for _, f in ipairs(fields) do
                if isHit(f) then
                    local d = describe(f)
                    if S.Announced[f] ~= d then
                        S.Announced[f] = d
                        S.Status = ("HIT  %s: %s"):format(f, d)
                        notify("HIT: " .. f, d)
                        playSfx()
                        if S.StopOnHit then stop = true end
                    end
                else
                    S.Announced[f] = nil
                    open[#open + 1] = f
                end
            end

            if stop then
                S.Spin = false
            elseif #fields == 0 then
                S.Status = "No fields enabled (or all skipped)"; S.Spin = false
            elseif #open == 0 then
                S.Status = "Selected fields are all already good"; S.Spin = false
            elseif Character.GetRerolls() <= 0 then
                S.Status = "Out of rerolls"; S.Spin = false
            else
                idx = idx % #open + 1
                local f = open[idx]
                local confirm = S.RollOver and needsConfirm(f)
                -- Ogre is Exotic, so the game protects it; rolling over it is the point of "Skip Ogre"
                if f == "FightStyle" and isSkippedOgre() then confirm = true end
                local hBefore = (f == "Height") and curHeight() or nil
                local ok, why = rollOnce(f, confirm)
                if ok then
                    fails = 0
                    S.Rolls += 1
                    S.Status = ("%s -> %s"):format(f, describe(f))
                    if f == "Height" and S.HeightUndo and hBefore then
                        task.wait(0.15)
                        local hNow = curHeight()
                        if hNow and hNow < hBefore then
                            local undone, reason = undoTo(hBefore)
                            if undone then
                                S.Undos += 1
                                S.Status = ("Height %s -> undone, kept %s"):format(ftin(hNow), ftin(hBefore))
                            else
                                S.Status = ("Undo failed (%s). Now at %s, was %s"):format(tostring(reason), ftin(curHeight() or 0), ftin(hBefore))
                                S.Spin = false
                            end
                        end
                    end
                elseif why == "holds_rare" then
                    S.Blocked[f] = true
                    S.Status = f .. ": current value is protected by the game, skipped (turn on 'Roll over non-target')"
                else
                    fails += 1
                    S.Status = ("%s rejected: %s"):format(f, why)
                    if fails >= 3 then S.Spin = false end
                    task.wait(0.5)
                end
            end
        end
    end
    pcall(function() rejConn:Disconnect() end)
end)

---------------------------------------------------------------- codes
local redeeming = false
local function redeemCodes()
    if redeeming then return end
    redeeming = true
    task.spawn(function()
        local bridge = BridgeNet2.ReferenceBridge(GS.Codes.Bridge)
        local last
        local conn = bridge:Connect(function(d)
            if typeof(d) == "table" and d.Action == "Status" then last = d end
        end)
        local okCount = 0
        for i, code in ipairs(CODES) do
            if S.Dead then break end
            last = nil
            S.Status = ("Codes %d/%d: %s"):format(i, #CODES, code)
            bridge:Fire({Action = "Redeem", Code = code})
            local t = os.clock()
            while not S.Dead and not last and os.clock() - t < 4 do task.wait(0.05) end
            if last and last.Ok then okCount += 1 end
            task.wait(1.6)
        end
        pcall(function() conn:Disconnect() end)
        S.Status = ("Codes done: %d/%d accepted"):format(okCount, #CODES)
        redeeming = false
    end)
end

---------------------------------------------------------------- UI
local parent = (gethui and gethui()) or CoreGui
local gui = Instance.new("ScreenGui")
gui.Name = "SGK_Menu"; gui.ResetOnSpawn = false; gui.DisplayOrder = 999
gui.Parent = parent
getgenv().SGK_Gui = gui

local BG, PANEL, GREEN, GRAY, TEXT = Color3.fromRGB(22, 22, 28), Color3.fromRGB(34, 34, 44), Color3.fromRGB(45, 150, 90), Color3.fromRGB(62, 62, 74), Color3.fromRGB(235, 235, 240)

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(260, 480); main.Position = UDim2.new(0, 30, 0.5, -240)
main.BackgroundColor3 = BG; main.BorderSizePixel = 0; main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -60, 0, 30); title.Position = UDim2.fromOffset(10, 0)
title.BackgroundTransparency = 1; title.Text = "Shigaku Auto Spin"; title.TextColor3 = TEXT
title.Font = Enum.Font.GothamBold; title.TextSize = 14; title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = main

local function smallBtn(txt, x, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(22, 22); b.Position = UDim2.new(1, x, 0, 4)
    b.BackgroundColor3 = GRAY; b.Text = txt; b.TextColor3 = TEXT; b.Font = Enum.Font.GothamBold; b.TextSize = 13
    b.BorderSizePixel = 0; b.Parent = main
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    b.MouseButton1Click:Connect(cb)
end

local body = Instance.new("ScrollingFrame")
body.Size = UDim2.new(1, -16, 1, -38); body.Position = UDim2.fromOffset(8, 32)
body.BackgroundTransparency = 1; body.BorderSizePixel = 0; body.ScrollBarThickness = 3
body.CanvasSize = UDim2.new(0, 0, 0, 0); body.AutomaticCanvasSize = Enum.AutomaticSize.Y; body.Parent = main
local layout = Instance.new("UIListLayout", body); layout.Padding = UDim.new(0, 5); layout.SortOrder = Enum.SortOrder.LayoutOrder

smallBtn("-", -52, function() body.Visible = not body.Visible; main.Size = body.Visible and UDim2.fromOffset(260, 480) or UDim2.fromOffset(260, 30) end)
smallBtn("X", -26, function()
    S.Dead = true; S.Spin = false
    pcall(function() if sfxSound then sfxSound:Destroy() end end)
    gui:Destroy()
end)

do
    local dragging, start, startPos
    title.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, start, startPos = true, i.Position, main.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - start
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local refreshers = {}
refreshAll = function() for _, r in ipairs(refreshers) do r() end end

local order = 0
local function nextOrder() order += 1; return order end

local function toggle(label, get, set, big)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -6, 0, big and 34 or 26); b.LayoutOrder = nextOrder()
    b.Font = Enum.Font.GothamBold; b.TextSize = big and 14 or 12; b.TextColor3 = TEXT; b.BorderSizePixel = 0
    b.Parent = body
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local function refresh()
        local on = get()
        b.Text = label .. ":  " .. (on and "ON" or "OFF")
        b.BackgroundColor3 = on and GREEN or GRAY
    end
    b.MouseButton1Click:Connect(function() set(not get()); refresh() end)
    refreshers[#refreshers + 1] = refresh
    refresh()
end

local function header(txt)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -6, 0, 18); l.LayoutOrder = nextOrder(); l.BackgroundTransparency = 1
    l.Text = txt; l.TextColor3 = Color3.fromRGB(150, 150, 170); l.Font = Enum.Font.GothamBold; l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = body
end

-- a "label: value  [-] [+]" row
local function stepper(text, get, minus, plus)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -6, 0, 26); row.LayoutOrder = nextOrder(); row.BackgroundColor3 = PANEL; row.BorderSizePixel = 0; row.Parent = body
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -60, 1, 0); lbl.Position = UDim2.fromOffset(8, 0); lbl.BackgroundTransparency = 1
    lbl.TextColor3 = TEXT; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row
    local function upd() lbl.Text = text .. get() end
    local function step(txt, x, fn)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(22, 20); b.Position = UDim2.new(1, x, 0, 3); b.BackgroundColor3 = GRAY
        b.Text = txt; b.TextColor3 = TEXT; b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.BorderSizePixel = 0; b.Parent = row
        b.MouseButton1Click:Connect(function() fn(); upd() end)
    end
    step("-", -52, minus); step("+", -26, plus); upd()
    refreshers[#refreshers + 1] = upd
end

toggle("AUTO SPIN", function() return S.Spin end, function(v)
    S.Spin = v
    if v then S.Announced = {}; S.Blocked = {}; S.Status = "Spinning..." else S.Status = "Paused" end
end, true)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -6, 0, 58); status.LayoutOrder = nextOrder(); status.BackgroundColor3 = PANEL
status.TextColor3 = TEXT; status.Font = Enum.Font.Gotham; status.TextSize = 12; status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left; status.TextYAlignment = Enum.TextYAlignment.Top
status.BorderSizePixel = 0; status.Parent = body
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 6)
Instance.new("UIPadding", status).PaddingLeft = UDim.new(0, 6)

header("STOP WHEN A ROLL IS GOOD FOR")
local labels = {
    FightStyle = "Fight Style (Exotic / Halloween)",
    Height = "Height",
    Ethnicity = "Ethnicity (tallest 3 only)",
    HairColor = "Hair color (Mythic)",
    Eyes = "Eyes (rare / heterochromia)",
    Gear = "Gear (Epic+ on any slot)",
}
for _, f in ipairs(ALL_FIELDS) do
    toggle(labels[f] or f, function() return S.Fields[f] end, function(v) S.Fields[f] = v; S.Blocked = {} end)
end

stepper("Min height: ", function() return ftin(S.MinHeight) end,
    function() S.MinHeight = math.clamp(S.MinHeight - 1, 48, 120) end,
    function() S.MinHeight = math.clamp(S.MinHeight + 1, 48, 120) end)

header("OPTIONS")
toggle("Heavenly sound on hit", function() return S.Sfx end, function(v) S.Sfx = v end)
stepper("Sound volume: ", function() return ("%.1f"):format(S.SfxVolume) end,
    function() S.SfxVolume = math.clamp(S.SfxVolume - 0.5, 0.5, 10) end,
    function() S.SfxVolume = math.clamp(S.SfxVolume + 0.5, 0.5, 10) end)

local tb = Instance.new("TextButton")
tb.Size = UDim2.new(1, -6, 0, 26); tb.LayoutOrder = nextOrder(); tb.BackgroundColor3 = Color3.fromRGB(60, 90, 170)
tb.Text = "Test sound"; tb.TextColor3 = TEXT; tb.Font = Enum.Font.GothamBold; tb.TextSize = 12; tb.BorderSizePixel = 0; tb.Parent = body
Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 6)
tb.MouseButton1Click:Connect(function()
    if not ensureSfx() then S.Status = "Sound failed to load (is sgk_heaven.mp3 in Real's workspace?)" return end
    playSfx(true)
end)

toggle("Skip Ogre (fight style)", function() return S.SkipOgre end, function(v) S.SkipOgre = v end)
toggle("Height: undo lower rolls", function() return S.HeightUndo end, function(v) S.HeightUndo = v end)
toggle("Stop on hit", function() return S.StopOnHit end, function(v) S.StopOnHit = v end)
toggle("Roll over non-target", function() return S.RollOver end, function(v) S.RollOver = v; S.Blocked = {} end)
toggle("Also stop on Legendary style", function() return S.LegendaryStyle end, function(v) S.LegendaryStyle = v end)
toggle("Auto redeem codes on load", function() return S.AutoCodes end, function(v) S.AutoCodes = v end)

local rb = Instance.new("TextButton")
rb.Size = UDim2.new(1, -6, 0, 28); rb.LayoutOrder = nextOrder(); rb.BackgroundColor3 = Color3.fromRGB(60, 90, 170)
rb.Text = "Redeem all codes now"; rb.TextColor3 = TEXT; rb.Font = Enum.Font.GothamBold; rb.TextSize = 12; rb.BorderSizePixel = 0; rb.Parent = body
Instance.new("UICorner", rb).CornerRadius = UDim.new(0, 6)
rb.MouseButton1Click:Connect(redeemCodes)

-- live refresh: buttons always show the real state
task.spawn(function()
    while not S.Dead do
        status.Text = ("Rerolls: %s   Rolls: %d   Undos: %d\n%s"):format(tostring(Character.GetRerolls()), S.Rolls, S.Undos, S.Status)
        refreshAll()
        task.wait(0.15)
    end
end)

if S.AutoCodes then redeemCodes() end
