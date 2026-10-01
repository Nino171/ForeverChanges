local ADDON, ns = ...

-- Teal overlay: a desaturated copy of the parchment tinted cfg.tint, fading from cfg.alpha at the
-- bottom to cfg.topAlpha at cfg.height of the way up. Settings live in the options panel.
ns.defaults = {
    showTint = true,   -- teal overlay on non-vanilla quests
    itemTint = true,
    spellTint = true,     -- teal glow on new and changed spells in the spellbook, trainer and tooltips
    spellVanilla = true,  -- orange lines in the tooltip of a changed spell showing how it was in vanilla
    tint = { 0.60, 0.90, 0.95 },
    alpha = 1.0,    -- opacity at the very bottom
    topAlpha = 0,   -- opacity where the fade ends
    height = 0.6,   -- fraction of the visible parchment (from the bottom) the fade covers
    marker = true,  -- prefix non-vanilla quests in the quest log list and tracker
    markerSymbol = "\226\136\158", -- infinity sign (UTF-8 bytes)
    markerAtStart = false, -- false: after the quest name, true: before it
    markerIcon = true,     -- draw the marker as an icon instead of the text symbol
    markerHeight = 8,      -- height of the infinity sign itself, in pixels (roughly the text's cap height)
    markerOffset = 0,      -- vertical nudge in pixels, relative to the built-in baseline (ICON_BASELINE)
    markerGap = 0,         -- extra space between the icon and the quest name, in pixels
    markerUseTint = true,
    markerColor = { 0.60, 0.90, 0.95 },
    objectiveTint = false,     -- recolour the objective lines of non-vanilla quests
    objectiveUseTint = true,   -- objectives use the tint colour...
    objectiveColor = { 0.60, 0.90, 0.95 }, -- ...or this colour
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
ns.cfg = CopyDefaults({}, ns.defaults)

local PANELS = {
    "QuestFrameDetailPanel",
    "QuestFrameProgressPanel",
    "QuestFrameRewardPanel",
    "QuestFrameGreetingPanel",
}
local SUFFIXES = { "Bg", "MaterialTopLeft", "MaterialTopRight", "MaterialBotLeft", "MaterialBotRight" }

local vanilla = {}
for _, r in ipairs(ns.VanillaQuestRanges) do
    for id = r[1], r[2] do
        vanilla[id] = true
    end
end

local REWARDS_OVERLAP = 24 -- how far the overlay tucks under the Rewards panel
-- Black Quest Text Contrast (setting 4) gives a dark panel; see ApplyOverlay.
local DARK_SCALE = 0.75 -- brightness of the teal on dark backgrounds
local DARK_ALPHA = 0.7  -- strength of the teal on dark backgrounds, relative to cfg.alpha
local BLACK_PANEL_ALPHA = 0.6 -- same for tooltips, the spellbook and the trainer, which are black

local function IsDarkBackground()
    if QuestTextContrast and QuestTextContrast.UseLightText then
        return QuestTextContrast.UseLightText() and true or false
    end
    return tonumber(GetCVar("QuestTextContrast") or 0) == 4
end

local overlays = setmetatable({}, { __mode = "k" })

local function ApplyOverlay(tex, tinted)
    local ov = overlays[tex]
    tinted = tinted and ns.cfg.showTint
    if not tinted then
        if ov then ov:Hide() end
        return
    end
    if not ov then
        ov = tex:GetParent():CreateTexture(nil, "BACKGROUND", nil, 2)
        overlays[tex] = ov
    end
    -- Bottom strip of the parchment only, so the fade finishes cfg.height of the way up.
    local l, r, t, b
    local atlas = tex:GetAtlas()
    local info = atlas and C_Texture.GetAtlasInfo(atlas)
    if info then
        l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    else
        local ulx, uly, _, _, _, _, lrx, lry = tex:GetTexCoord()
        l, r, t, b = ulx, lrx, uly, lry
    end
    -- The Rewards panel (log window) slides over the bottom of the parchment, so measure
    -- from the bottom of the *visible* parchment and map the texture coords to match.
    local bgTop, bgBottom = tex:GetTop(), tex:GetBottom()
    if not bgTop or not bgBottom or bgTop <= bgBottom then
        ov:Hide()
        return
    end
    local visBottom = bgBottom
    local rewards = tex:GetParent().RewardsFrameContainer
    local rewardsTop = rewards and rewards:IsShown() and rewards:GetTop()
    if rewardsTop then
        -- Run underneath the Rewards panel: its rim starts below its reported top edge.
        rewardsTop = rewardsTop - REWARDS_OVERLAP
        if rewardsTop > visBottom then
            visBottom = math.min(rewardsTop, bgTop - 1)
        end
    end
    local total = bgTop - bgBottom
    local cfg = ns.cfg
    local height = (bgTop - visBottom) * cfg.height
    local vBot = t + (b - t) * ((bgTop - visBottom) / total)
    local vTop = t + (b - t) * ((bgTop - visBottom - height) / total)
    ov:ClearAllPoints()
    ov:SetPoint("BOTTOMLEFT", tex, "BOTTOMLEFT", 0, visBottom - bgBottom)
    ov:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, visBottom - bgBottom)
    ov:SetHeight(height)
    local c = cfg.tint
    if IsDarkBackground() then
        -- On the Black contrast setting a multiplied copy of the background would stay black,
        -- so draw a flat, deeper teal glow instead.
        ov:SetColorTexture(1, 1, 1, 1)
        ov:SetGradient("VERTICAL",
            CreateColor(c[1] * DARK_SCALE, c[2] * DARK_SCALE, c[3] * DARK_SCALE, cfg.alpha * DARK_ALPHA),
            CreateColor(c[1] * DARK_SCALE, c[2] * DARK_SCALE, c[3] * DARK_SCALE, cfg.topAlpha * DARK_ALPHA))
    else
        ov:SetTexture(info and (info.file or info.filename) or tex:GetTexture())
        ov:SetTexCoord(l, r, vTop, vBot)
        ov:SetDesaturated(true)
        ov:SetGradient("VERTICAL",
            CreateColor(c[1], c[2], c[3], cfg.alpha),
            CreateColor(c[1], c[2], c[3], cfg.topAlpha))
    end
    ov:Show()
end

-- Quest Text Contrast (Default/Brown/White/Grey/Black) swaps the background atlas, so match
-- the whole family: QuestDetailsBackgrounds[-Accessibility...] and QuestBG-Parchment[-Accessibility...].
local function IsParchment(tex)
    local atlas = tex:GetAtlas()
    if not atlas then return false end
    atlas = atlas:lower()
    return atlas:find("^questdetailsbackgrounds") ~= nil or atlas:find("^questbg%-parchment") ~= nil
end

local function Walk(frame, fn, seen)
    if seen[frame] then return end
    seen[frame] = true
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetTexture then fn(region) end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        Walk(child, fn, seen)
    end
end

local function SetTinted(tinted)
    -- The window has several parchment-like textures (one per panel); overlay all of them.
    local candidates = {}
    if QuestFrame then
        Walk(QuestFrame, function(tex)
            if IsParchment(tex) then candidates[#candidates + 1] = tex end
        end, {})
    end
    for _, panel in ipairs(PANELS) do
        for _, suffix in ipairs(SUFFIXES) do
            local tex = _G[panel .. suffix]
            if tex and tex:IsShown() then candidates[#candidates + 1] = tex end
        end
    end
    for _, tex in ipairs(candidates) do
        ApplyOverlay(tex, tinted)
    end
end

local currentTint = false

local function Refresh()
    if QuestFrame and QuestFrame:IsShown() then
        SetTinted(currentTint)
    end
end

local function Update()
    local id = GetQuestID()
    currentTint = id and id > 0 and not vanilla[id] or false
    Refresh()
    -- Blizzard may re-apply quest materials after the event fires.
    C_Timer.After(0, Refresh)
end

local f = CreateFrame("Frame")
f:RegisterEvent("QUEST_DETAIL")
f:RegisterEvent("QUEST_PROGRESS")
f:RegisterEvent("QUEST_COMPLETE")
f:RegisterEvent("QUEST_GREETING")
f:SetScript("OnEvent", function(_, event)
    if event == "QUEST_GREETING" then
        currentTint = false
        Refresh()
    else
        Update()
    end
end)

if QuestFrame then
    QuestFrame:HookScript("OnShow", Refresh)
end

-- Map & Quest Log: the parchment is QuestMapFrame...DetailsFrame.Bg (atlas QuestDetailsBackgrounds).
local logBg, logTinted
local function TintLogFrame(tinted)
    if not QuestMapFrame then return end
    logTinted = tinted
    -- Blizzard's own key for the parchment; works whatever atlas the contrast setting uses.
    local details = QuestMapFrame.DetailsFrame
    local bg = details and details.Bg
    if bg and bg.GetTexture then
        logBg = bg
        ApplyOverlay(bg, tinted)
        return
    end
    Walk(QuestMapFrame, function(tex)
        if IsParchment(tex) then
            logBg = tex
            ApplyOverlay(tex, tinted)
        end
    end, {})
end

-- Blizzard re-lays out the details panel when it scrolls, which drops the overlay;
-- keep it applied while a tinted quest is showing.
local elapsed = 0
local keeper = CreateFrame("Frame")
keeper:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.05 then return end
    elapsed = 0
    if logTinted and logBg and logBg:IsVisible() then
        ApplyOverlay(logBg, true)
    end
end)

local function RefreshLog()
    local details = QuestMapFrame and QuestMapFrame.DetailsFrame
    local id = details and details:IsShown() and details.questID
    TintLogFrame(id and id > 0 and not vanilla[id] or false)
end

local logHooked = false
local function HookLog()
    if logHooked or not QuestMapFrame then return end
    logHooked = true
    QuestMapFrame:HookScript("OnShow", RefreshLog)
    if QuestMapFrame.DetailsFrame then
        QuestMapFrame.DetailsFrame:HookScript("OnShow", RefreshLog)
        QuestMapFrame.DetailsFrame:HookScript("OnHide", RefreshLog)
    end
    if QuestMapFrame_ShowQuestDetails then
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", function()
            RefreshLog()
            C_Timer.After(0, RefreshLog)
        end)
    end
    if QuestMapFrame_CloseQuestDetails then
        hooksecurefunc("QuestMapFrame_CloseQuestDetails", RefreshLog)
    end
end

-- Marker (default: an infinity sign) in front of non-vanilla quest names in the quest log
-- list and the objective tracker.
local function IsNonVanilla(questID)
    return questID and questID > 0 and not vanilla[questID]
end

local ICON_PATH = "Interface\\AddOns\\ForeverChanges\\Media\\Infinity.tga"
-- The visible infinity sign inside Infinity.tga (a 64x64 image), in pixels.
local ICON_L, ICON_R, ICON_T, ICON_B = 1, 63, 12, 51
local ICON_ASPECT = (ICON_R - ICON_L) / (ICON_B - ICON_T)
-- The icon is drawn this many pixels lower than centred so it sits on the text baseline. The
-- "Icon vertical position" option is relative to this.
local ICON_BASELINE = -2

local function MarkerGlyph()
    local cfg = ns.cfg
    local c = cfg.markerUseTint and cfg.tint or cfg.markerColor
    local r, g, b = math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)
    if cfg.markerIcon then
        -- |T path : height : width : offX : offY : texW : texH : left : right : top : bottom : red : green : blue |t
        -- The texture is cropped to the infinity sign itself, so "height" is the visible height.
        local h = cfg.markerHeight
        local w = math.floor(h * ICON_ASPECT + 0.5)
        -- The x offset moves the drawn image without changing the text layout, so a positive gap
        -- pushes an icon after the name away from it (and a negative one, for an icon before it).
        local offX = cfg.markerAtStart and -cfg.markerGap or cfg.markerGap
        return ("|T%s:%d:%d:%d:%d:64:64:%d:%d:%d:%d:%d:%d:%d|t"):format(
            ICON_PATH, h, w, offX, cfg.markerOffset + ICON_BASELINE, ICON_L, ICON_R, ICON_T, ICON_B, r, g, b)
    end
    return ("|cff%02x%02x%02x%s|r"):format(r, g, b, cfg.markerSymbol)
end

-- Sets fs's text to the marked (or original) version. Remembers the original so this can be
-- re-run safely, including after Blizzard rewrites the text. With padBlock, an entry whose
-- marker adds a wrapped line also gets its block made taller by that line, because the tracker
-- measured the block before the marker was added.
local function ApplyMarker(fs, wanted, padBlock)
    local cur = fs:GetText()
    if not cur then return end
    local base = cur
    if fs.fchMarked and cur == fs.fchMarked then
        base = fs.fchBase
    end
    local new = base
    local useMarker = wanted and ns.cfg.marker and (ns.cfg.markerIcon or ns.cfg.markerSymbol ~= "")
    if useMarker then
        if ns.cfg.markerAtStart then
            new = MarkerGlyph() .. " " .. base
        else
            new = base .. " " .. MarkerGlyph()
        end
    end
    fs.fchBase = base
    if new ~= cur then
        fs.fchPad = 0
        if padBlock and useMarker and fs.GetStringHeight then
            fs:SetText(base)
            local baseHeight = fs:GetStringHeight()
            fs:SetText(new)
            fs.fchPad = math.max(0, fs:GetStringHeight() - baseHeight)
        else
            fs:SetText(new)
        end
    end
    fs.fchMarked = new

    if padBlock then
        local block = fs.GetParent and fs:GetParent()
        local pad = useMarker and fs.fchPad or 0
        if block and block.SetHeight then
            local h = block:GetHeight()
            if pad > 0 then
                -- Blizzard resets the block's height whenever it lays out the tracker, so
                -- re-add the padding whenever the height is not the padded one.
                if not block.fchPaddedHeight or math.abs(h - block.fchPaddedHeight) > 0.5 then
                    block:SetHeight(h + pad)
                    block.fchPaddedHeight = h + pad
                end
            elseif block.fchPaddedHeight then
                if math.abs(h - block.fchPaddedHeight) <= 0.5 then
                    block:SetHeight(h - (fs.fchLastPad or 0))
                end
                block.fchPaddedHeight = nil
            end
            fs.fchLastPad = pad
        end
    end
end

-- Objective lines ("- 0/5 Darkhound Blood"): optionally recoloured for non-vanilla quests. Only
-- lines that are the default white/grey are touched, so completed (green) or failed (red)
-- objectives keep their colour.
local function ObjectiveRGB()
    local cfg = ns.cfg
    local c = cfg.objectiveUseTint and cfg.tint or cfg.objectiveColor
    return c[1], c[2], c[3]
end

local function IsDefaultTextColour(r, g, b)
    return math.max(r, g, b) > 0.6 and math.max(r, g, b) - math.min(r, g, b) < 0.12
end

local function Near(a, b)
    return math.abs(a - b) < 0.01
end

local function SetObjectiveColour(fs, on)
    if not fs.GetTextColor then return end
    local cr, cg, cb, ca = fs:GetTextColor()
    if not cr then return end
    if on then
        local r, g, b = ObjectiveRGB()
        if Near(cr, r) and Near(cg, g) and Near(cb, b) then return end
        if IsDefaultTextColour(cr, cg, cb) or fs.fchOrigColour then
            -- Remember the colour Blizzard chose, once, so it can be put back.
            if not fs.fchOrigColour or IsDefaultTextColour(cr, cg, cb) then
                fs.fchOrigColour = { cr, cg, cb, ca or 1 }
            end
            fs:SetTextColor(r, g, b)
        end
    elseif fs.fchOrigColour then
        local o = fs.fchOrigColour
        fs.fchOrigColour = nil
        local r, g, b = ObjectiveRGB()
        if Near(cr, r) and Near(cg, g) and Near(cb, b) then
            fs:SetTextColor(o[1], o[2], o[3], o[4])
        end
    end
end

local function ColourLogObjectives()
    local pool = QuestScrollFrame and QuestScrollFrame.objectiveFramePool
    if not pool then return end
    for frame in pool:EnumerateActive() do
        if frame.Text then
            SetObjectiveColour(frame.Text, ns.cfg.objectiveTint and IsNonVanilla(frame.questID) and true or false)
        end
    end
end

local function RefreshLogList()
    if not QuestScrollFrame or not QuestScrollFrame.titleFramePool then return end
    for button in QuestScrollFrame.titleFramePool:EnumerateActive() do
        if button.Text then
            ApplyMarker(button.Text, IsNonVanilla(button.questID))
        end
    end
    ColourLogObjectives()
end

-- Quest log access differs between clients: prefer C_QuestLog, fall back to the old globals.
local function NumLogEntries()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        return (C_QuestLog.GetNumQuestLogEntries())
    end
    return GetNumQuestLogEntries and (GetNumQuestLogEntries()) or 0
end

local function LogEntry(i)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(i)
        if info then return info.title, info.isHeader, info.questID end
        return
    end
    if GetQuestLogTitle then
        local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
        return title, isHeader, questID
    end
end

local titleMap
local function BuildTitleMap()
    titleMap = {}
    for i = 1, NumLogEntries() do
        local title, isHeader, questID = LogEntry(i)
        if title and not isHeader then
            -- A title shared with a vanilla quest counts as vanilla.
            if titleMap[title] == nil then
                titleMap[title] = IsNonVanilla(questID) and true or false
            elseif not IsNonVanilla(questID) then
                titleMap[title] = false
            end
        end
    end
end

-- Tracker headers can carry a quest ID ("123 - Title") and/or a level ("[8] Title").
local function StripPrefixes(text)
    -- The tracker wraps names in colour codes ("|cffffd100[6] Title|r") and may add icons.
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("^%s+", "")
    text = text:gsub("^%d+ %- ", "")
    text = text:gsub("^%[[^%]]*%]%s*", "")
    return text
end

local function TrackerSetLine(line, _, _, isHeader, text)
    if not isHeader or type(text) ~= "string" then return end
    if not titleMap then BuildTitleMap() end
    local wanted = titleMap[text] or titleMap[StripPrefixes(text)]
    ApplyMarker(line.text, wanted)
end

-- The objective tracker differs between clients, so as well as hooking the older WatchFrame
-- function, look through the tracker's text lines a few times a second and mark quest names.
local function ColourBlockObjectives(block, headerFs, on)
    for _, region in ipairs({ block:GetRegions() }) do
        if region ~= headerFs and region.GetObjectType and region:GetObjectType() == "FontString" then
            SetObjectiveColour(region, on)
        end
    end
    for _, child in ipairs({ block:GetChildren() }) do
        ColourBlockObjectives(child, headerFs, on)
    end
end

local function ScanTracker(frame, seen)
    if seen[frame] then return end
    seen[frame] = true
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            local text = region:GetText()
            if text and text ~= "" then
                local base = (region.fchMarked and text == region.fchMarked) and region.fchBase or text
                local wanted = titleMap[base] or titleMap[StripPrefixes(base)]
                if wanted or region.fchMarked then
                    ApplyMarker(region, wanted, true)
                end
                local colourOn = wanted and ns.cfg.objectiveTint
                if colourOn or region.fchColouredBlock then
                    local block = region.GetParent and region:GetParent()
                    if colourOn and block then
                        ColourBlockObjectives(block, region, true)
                        region.fchColouredBlock = block
                    elseif region.fchColouredBlock then
                        ColourBlockObjectives(region.fchColouredBlock, region, false)
                        region.fchColouredBlock = nil
                    end
                end
            end
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        ScanTracker(child, seen)
    end
end

local scanElapsed = 0
local pollFailed = false
local function ScanOnce()
    local root = ObjectiveTrackerFrame or WatchFrame
    if not root or not root:IsVisible() then return end
    if not titleMap then BuildTitleMap() end
    ScanTracker(root, {})
end

local function ScanOnceWrapper()
    ScanOnce()
    if ns.cfg.objectiveTint and QuestMapFrame and QuestMapFrame:IsVisible() then
        ColourLogObjectives()
    end
end

local function TrackerPoll(_, dt)
    if pollFailed then return end
    scanElapsed = scanElapsed + dt
    if scanElapsed < 0.1 then return end
    scanElapsed = 0
    -- If this ever errors, report it once and stop rather than erroring four times a second.
    local ok, err = pcall(ScanOnceWrapper)
    if not ok then
        pollFailed = true
        print("|cffff5555Forever Changes:|r tracker markers disabled after an error: " .. tostring(err))
    end
end

local function RefreshTracker()
    if WatchFrame_Update and WatchFrame and not InCombatLockdown() then
        titleMap = nil
        WatchFrame_Update()
    end
end

local listHooked, trackerHooked, eventsHooked = false, false, false
local function HookMarkers()
    -- Each hook installs independently, so a missing function in one doesn't block the other.
    if not listHooked and QuestLogQuests_Update then
        listHooked = true
        hooksecurefunc("QuestLogQuests_Update", RefreshLogList)
    end
    if not trackerHooked and WatchFrame_SetLine then
        trackerHooked = true
        hooksecurefunc("WatchFrame_SetLine", TrackerSetLine)
    end
    if not eventsHooked then
        eventsHooked = true
        CreateFrame("Frame"):SetScript("OnUpdate", TrackerPoll)
        local ev = CreateFrame("Frame")
        for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
            ev:RegisterEvent(e)
        end
        ev:SetScript("OnEvent", function() titleMap = nil end)
    end
end

-- Tooltips, the spellbook and the trainer are black, so they get a flat teal glow rising from the bottom.
local function GlowColors()
    local cfg = ns.cfg
    local c = cfg.tint
    local r, g, b = c[1] * DARK_SCALE, c[2] * DARK_SCALE, c[3] * DARK_SCALE
    return CreateColor(r, g, b, cfg.alpha * BLACK_PANEL_ALPHA), CreateColor(r, g, b, cfg.topAlpha * BLACK_PANEL_ALPHA)
end

-- Item tooltips: all new items added in WoW Forever get the teal glow.
local VANILLA_MAX_ITEM_ID = 24283
local TOOLTIP_INSET = 3
local itemGlows = setmetatable({}, { __mode = "k" })

local function IsNonVanillaItem(itemID)
    return itemID and itemID > VANILLA_MAX_ITEM_ID
end

local function SetTooltipGlow(tooltip, show)
    local glow = itemGlows[tooltip]
    if not show then
        if glow then glow:Hide() end
        return
    end
    if not glow then
        glow = tooltip:CreateTexture(nil, "ARTWORK", nil, -8)
        glow:SetColorTexture(1, 1, 1, 1)
        glow:SetPoint("BOTTOMLEFT", TOOLTIP_INSET, TOOLTIP_INSET)
        glow:SetPoint("BOTTOMRIGHT", -TOOLTIP_INSET, TOOLTIP_INSET)
        itemGlows[tooltip] = glow
        tooltip:HookScript("OnTooltipCleared", function() glow:Hide() end)
        tooltip:HookScript("OnSizeChanged", function(self)
            glow:SetHeight(math.max(1, self:GetHeight() * ns.cfg.height))
        end)
    end
    glow:SetHeight(math.max(1, tooltip:GetHeight() * ns.cfg.height))
    glow:SetGradient("VERTICAL", GlowColors())
    glow:Show()
end

-- Spells: ns.NewSpells / ns.ChangedSpells come from SpellData.lua. A changed spell's value is how
-- it was in vanilla (when known exactly), which is added to its tooltip in orange.
local VANILLA_R, VANILLA_G, VANILLA_B = 1, 0.55, 0.15

local function IsMarkedSpell(spellID)
    return spellID and (ns.NewSpells[spellID] or ns.ChangedSpells[spellID] ~= nil) and true or false
end

local function OnSpellTooltip(tooltip, data)
    local id = data and data.id
    if tooltip.CreateTexture then
        SetTooltipGlow(tooltip, ns.cfg.spellTint and IsMarkedSpell(id))
    end
    local vanilla = ns.cfg.spellVanilla and id and ns.ChangedSpells[id]
    if type(vanilla) == "string" then
        for line in vanilla:gmatch("[^\n]+") do
            tooltip:AddLine(line, VANILLA_R, VANILLA_G, VANILLA_B, true)
        end
    end
end

local function HookItemTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip.CreateTexture then
                SetTooltipGlow(tooltip, ns.cfg.itemTint and IsNonVanillaItem(data and data.id))
            end
        end)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, OnSpellTooltip)
        return
    end
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
        tooltip:HookScript("OnTooltipSetItem", function(self)
            local _, link = self:GetItem()
            local id = link and tonumber(link:match("item:(%d+)"))
            SetTooltipGlow(self, ns.cfg.itemTint and IsNonVanillaItem(id))
        end)
    end
end
HookItemTooltips()

-- Spellbook entries and trainer rows: a soft teal glow along the bottom of the entry. Glow.tga fades
-- out at every edge, so the glow reaches past the entry a little to fill it.
local GLOW_PATH = "Interface/AddOns/ForeverChanges/Media/Glow.tga"
local GLOW_OUTSET_X, GLOW_OUTSET_Y = 10, 6
local rowGlows = setmetatable({}, { __mode = "k" })

local function SetRowGlow(frame, anchor, show, layer)
    local glow = rowGlows[frame]
    if not show then
        if glow then glow:Hide() end
        return
    end
    if not glow then
        glow = frame:CreateTexture(nil, layer, nil, 1)
        glow:SetTexture(GLOW_PATH)
        rowGlows[frame] = glow
    end
    local height = anchor:GetHeight()
    if not height or height < 1 then height = frame:GetHeight() end
    glow:ClearAllPoints()
    glow:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -GLOW_OUTSET_X, -GLOW_OUTSET_Y)
    glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", GLOW_OUTSET_X, -GLOW_OUTSET_Y)
    glow:SetHeight(math.max(1, height * ns.cfg.height + GLOW_OUTSET_Y))
    glow:SetGradient("VERTICAL", GlowColors())
    glow:Show()
end

local function TintSpellBookItem(item)
    local info = item.spellBookItemInfo
    SetRowGlow(item, item.Backplate or item, ns.cfg.spellTint and info and IsMarkedSpell(info.spellID), "BACKGROUND")
end

local function RefreshSpellBook()
    local book = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
    if book and book.ForEachDisplayedSpell then
        book:ForEachDisplayedSpell(TintSpellBookItem)
    end
end

local spellBookHooked = false
local function HookSpellBook()
    -- The spellbook loads on demand; its entries copy these methods when they are created, so hook first.
    if spellBookHooked or not SpellBookItemMixin then return end
    spellBookHooked = true
    hooksecurefunc(SpellBookItemMixin, "UpdateVisuals", TintSpellBookItem)
    hooksecurefunc(SpellBookItemMixin, "ClearSpellData", function(item)
        SetRowGlow(item, nil, false)
    end)
    RefreshSpellBook()
end

local function TintTrainerButton(button, skillIndex)
    local show = false
    if ns.cfg.spellTint and skillIndex and C_TooltipInfo and C_TooltipInfo.GetTrainerService then
        local ok, data = pcall(C_TooltipInfo.GetTrainerService, skillIndex)
        show = ok and data and IsMarkedSpell(data.id)
    end
    -- ARTWORK sits above the row's background texture.
    SetRowGlow(button, button, show, "ARTWORK")
end

local function RefreshTrainer()
    local box = ClassTrainerFrame and ClassTrainerFrame.ScrollBox
    if not (box and box.ForEachFrame and ClassTrainerFrame:IsShown()) then return end
    box:ForEachFrame(function(button)
        if button.nameSubText then TintTrainerButton(button, button:GetID()) end
    end)
end

local trainerHooked = false
local function HookTrainer()
    if trainerHooked or not ClassTrainerFrame_InitServiceButton then return end
    trainerHooked = true
    hooksecurefunc("ClassTrainerFrame_InitServiceButton", function(button, elementData)
        elementData = elementData and (elementData.data or elementData)
        TintTrainerButton(button, elementData and elementData.skillIndex)
    end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        local db = ForeverChangesDB or {}
        ForeverChangesDB = CopyDefaults(db, ns.defaults)
        ns.cfg = ForeverChangesDB
    end
    HookLog()
    HookMarkers()
    HookSpellBook()
    HookTrainer()
end)
HookLog()
HookMarkers()
HookSpellBook()
HookTrainer()


-- Called by the options panel after any setting changes.
function ns.Reapply()
    Refresh()
    RefreshLog()
    RefreshLogList()
    RefreshTracker()
    RefreshSpellBook()
    RefreshTrainer()
end

SLASH_FCHANGES1 = "/fchanges"
SlashCmdList.FCHANGES = function(msg)
    if msg == "hooks" then
        print(("Forever Changes hooks: quest log list=%s (QuestLogQuests_Update %s), tracker=%s (WatchFrame_SetLine %s), marker=%s")
            :format(tostring(listHooked), tostring(QuestLogQuests_Update ~= nil), tostring(trackerHooked),
                tostring(WatchFrame_SetLine ~= nil), tostring(ns.cfg.marker)))
        return
    end
    if msg == "id" then
        -- Handy for reporting a vanilla quest that is wrongly tinted.
        local id = GetQuestID()
        local details = QuestMapFrame and QuestMapFrame.DetailsFrame
        local logID = details and details.questID
        local bg = QuestMapFrame and QuestMapFrame.DetailsFrame and QuestMapFrame.DetailsFrame.Bg
        print("Forever Changes: log parchment atlas = " .. tostring(bg and bg:GetAtlas()) .. ", file = " .. tostring(bg and bg:GetTexture()))
        print(("Forever Changes: dialog quest id %s (vanilla=%s), log quest id %s (vanilla=%s)"):format(
            tostring(id), tostring(id and vanilla[id] or false), tostring(logID), tostring(logID and vanilla[logID] or false)))
        return
    end
    if ns.OpenOptions then ns.OpenOptions() end
end
