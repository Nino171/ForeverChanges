local ADDON, ns = ...

-- Teal overlay: a desaturated copy of the parchment tinted cfg.tint, fading from cfg.alpha at the
-- bottom to cfg.topAlpha at cfg.height of the way up. Settings live in the options panel.
ns.defaults = {
    showTint = true,   -- teal overlay on non-vanilla quests
    showLogo = false,  -- WoW Forever logo above the quest text on non-vanilla quests
    tint = { 0.60, 0.90, 0.95 },
    alpha = 1.0,    -- opacity at the very bottom
    topAlpha = 0,   -- opacity where the fade ends
    height = 0.6,   -- fraction of the visible parchment (from the bottom) the fade covers
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

local function IsDarkBackground()
    if QuestTextContrast and QuestTextContrast.UseLightText then
        return QuestTextContrast.UseLightText() and true or false
    end
    return tonumber(GetCVar("QuestTextContrast") or 0) == 4
end

local LOGO_PATH = "Interface/AddOns/ForeverQuestTint/Media/ForeverLogo.tga"
local logos = setmetatable({}, { __mode = "k" })

-- Logo: a small badge in the top-right corner of the bar just above the quest text.
-- It lives in its own high-level frame so Blizzard's window art can't cover it.
local LOGO_SIZE = 40
local GIVER_LOGO_X = 26 -- quest-giver window: pushes the logo out to the right end of the bar
local GIVER_LOGO_Y = -1 -- quest-giver window: vertical offset above the parchment (negative = lower)
local LOG_LOGO_Y = -22 -- fallback vertical offset from the log parchment's top edge

-- Frames are ordered by strata first, then level. Find the topmost (strata, level) anywhere in
-- a window so the logo can be drawn above all of its art.
local STRATA_ORDER = {
    BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}
local function TopOrder(frame, bestStrata, bestLevel)
    local strata = frame:GetFrameStrata()
    local level = frame:GetFrameLevel()
    local si, bi = STRATA_ORDER[strata] or 0, STRATA_ORDER[bestStrata] or 0
    if si > bi or (si == bi and level > bestLevel) then
        bestStrata, bestLevel = strata, level
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        bestStrata, bestLevel = TopOrder(child, bestStrata, bestLevel)
    end
    return bestStrata, bestLevel
end

local function ApplyLogo(tex, show)
    local holder = logos[tex]
    if not show then
        if holder then holder:Hide() end
        return
    end
    if not holder then
        -- Parent to the outermost window frame: the details frame itself may clip its children,
        -- and the bar above the parchment is outside its rectangle.
        local top = tex:GetParent()
        while top:GetParent() and top:GetParent() ~= UIParent do
            top = top:GetParent()
        end
        holder = CreateFrame("Frame", nil, top)
        local strata, level = TopOrder(top, "BACKGROUND", 0)
        holder:SetFrameStrata(strata)
        holder:SetFrameLevel(math.min(level + 1, 9999))
        holder:SetSize(LOGO_SIZE, LOGO_SIZE)
        holder.texture = holder:CreateTexture(nil, "OVERLAY")
        holder.texture:SetAllPoints()
        holder.texture:SetTexture(LOGO_PATH)
        logos[tex] = holder
    end
    holder:ClearAllPoints()
    local details = QuestMapFrame and QuestMapFrame.DetailsFrame
    if details and tex:GetParent() == details then
        -- Quest log: the parchment art has transparent padding above the paper, so line the logo
        -- up with the Back button instead (falls back to a fixed offset if it can't be found).
        local yOff = LOG_LOGO_Y
        local back = details.BackButton or QuestMapFrame.BackButton
        local top = tex:GetTop()
        if back and back.GetCenter and top then
            local _, cy = back:GetCenter()
            if cy then yOff = cy - top end
        end
        holder:SetPoint("RIGHT", tex, "TOPRIGHT", -6, yOff)
    else
        holder:SetPoint("BOTTOMRIGHT", tex, "TOPRIGHT", GIVER_LOGO_X, GIVER_LOGO_Y)
    end
    holder:Show()
end

local overlays = setmetatable({}, { __mode = "k" })

local function ApplyOverlay(tex, tinted, noLogo)
    local ov = overlays[tex]
    ApplyLogo(tex, tinted and ns.cfg.showLogo and not noLogo)
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
    -- The window has several parchment-like textures (one per panel); overlay all of them,
    -- but show the logo only once, on the largest visible one.
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
    local best, bestArea = nil, 0
    for _, tex in ipairs(candidates) do
        local area = tex:IsVisible() and (tex:GetWidth() * tex:GetHeight()) or 0
        if area > bestArea then best, bestArea = tex, area end
    end
    for _, tex in ipairs(candidates) do
        ApplyOverlay(tex, tinted, tex ~= best)
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
    elseif logBg then
        ApplyLogo(logBg, false)
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

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        ForeverQuestTintDB = CopyDefaults(ForeverQuestTintDB or {}, ns.defaults)
        ns.cfg = ForeverQuestTintDB
    end
    HookLog()
end)
HookLog()

-- Called by the options panel after any setting changes.
function ns.Reapply()
    Refresh()
    RefreshLog()
end

SLASH_FQT1 = "/fqt"
SlashCmdList.FQT = function(msg)
    if msg == "logo" then
        local h = logBg and logos[logBg]
        if not h then print("Forever Quest Tint: no log logo frame yet (tick 'Add logo', open a non-vanilla quest in the log)"); return end
        local pt, rel, relPt, x, y = h:GetPoint()
        print(("Forever Quest Tint logo: shown=%s visible=%s parent=%s level=%s strata=%s size=%dx%d alpha=%s point=%s to %s %s (%s,%s) left=%s bottom=%s tex=%s"):format(
            tostring(h:IsShown()), tostring(h:IsVisible()), tostring(h:GetParent():GetName() or h:GetParent():GetDebugName()),
            tostring(h:GetFrameLevel()), tostring(h:GetFrameStrata()), h:GetWidth(), h:GetHeight(), tostring(h:GetEffectiveAlpha()),
            tostring(pt), tostring(rel and (rel.GetDebugName and rel:GetDebugName())), tostring(relPt), tostring(x), tostring(y),
            tostring(h:GetLeft()), tostring(h:GetBottom()), tostring(h.texture:GetTexture())))
        return
    end
    if msg == "id" then
        -- Handy for reporting a vanilla quest that is wrongly tinted.
        local id = GetQuestID()
        local details = QuestMapFrame and QuestMapFrame.DetailsFrame
        local logID = details and details.questID
        local bg = QuestMapFrame and QuestMapFrame.DetailsFrame and QuestMapFrame.DetailsFrame.Bg
        print("Forever Quest Tint: log parchment atlas = " .. tostring(bg and bg:GetAtlas()) .. ", file = " .. tostring(bg and bg:GetTexture()))
        print(("Forever Quest Tint: dialog quest id %s (vanilla=%s), log quest id %s (vanilla=%s)"):format(
            tostring(id), tostring(id and vanilla[id] or false), tostring(logID), tostring(logID and vanilla[logID] or false)))
        return
    end
    if ns.OpenOptions then ns.OpenOptions() end
end
