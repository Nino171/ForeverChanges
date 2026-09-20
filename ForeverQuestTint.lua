local ADDON, ns = ...

-- Teal overlay: a desaturated copy of the parchment tinted cfg.tint, fading from cfg.alpha at the
-- bottom to cfg.topAlpha at cfg.height of the way up. Settings live in the options panel.
ns.defaults = {
    enabled = true,
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
local overlays = setmetatable({}, { __mode = "k" })

local function ApplyOverlay(tex, tinted)
    local ov = overlays[tex]
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
    ov:SetTexture(info and (info.file or info.filename) or tex:GetTexture())
    ov:SetTexCoord(l, r, vTop, vBot)
    ov:SetDesaturated(true)
    ov:SetGradient("VERTICAL",
        CreateColor(cfg.tint[1], cfg.tint[2], cfg.tint[3], cfg.alpha),
        CreateColor(cfg.tint[1], cfg.tint[2], cfg.tint[3], cfg.topAlpha))
    ov:Show()
end

local function IsParchment(tex)
    local atlas = tex:GetAtlas()
    return atlas and atlas:lower() == "questdetailsbackgrounds"
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
    if QuestFrame then
        Walk(QuestFrame, function(tex)
            if IsParchment(tex) then ApplyOverlay(tex, tinted) end
        end, {})
    end
    for _, panel in ipairs(PANELS) do
        for _, suffix in ipairs(SUFFIXES) do
            local tex = _G[panel .. suffix]
            if tex and tex:IsShown() then ApplyOverlay(tex, tinted) end
        end
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
    currentTint = ns.cfg.enabled and id and id > 0 and not vanilla[id] or false
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
    TintLogFrame(ns.cfg.enabled and id and id > 0 and not vanilla[id] or false)
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
    if msg == "id" then
        -- Handy for reporting a vanilla quest that is wrongly tinted.
        local id = GetQuestID()
        local details = QuestMapFrame and QuestMapFrame.DetailsFrame
        local logID = details and details.questID
        print(("Forever Quest Tint: dialog quest id %s (vanilla=%s), log quest id %s (vanilla=%s)"):format(
            tostring(id), tostring(id and vanilla[id] or false), tostring(logID), tostring(logID and vanilla[logID] or false)))
        return
    end
    if ns.OpenOptions then ns.OpenOptions() end
end
