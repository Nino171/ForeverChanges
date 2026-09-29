local ADDON, ns = ...

local panel = CreateFrame("Frame")
panel.name = "Forever Quest Tint"

local syncing = false
local widgets = {}
local sliderScale = {}
local Sync

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Forever Quest Tint")

local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
sub:SetText("Marks quests that were not in original Classic: a teal tint on the quest text background, and/or the WoW Forever logo.\nOpen a non-vanilla quest in the Map & Quest Log to preview changes.")
sub:SetJustifyH("LEFT")

-- Independent on/off options
local function MakeCheck(label, key, anchor, x, y)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
    cb.text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetText(label)
    cb:SetScript("OnClick", function(self)
        if syncing then return end
        ns.cfg[key] = self:GetChecked() and true or false
        ns.Reapply()
    end)
    widgets[key] = cb
    return cb
end
local showTint = MakeCheck("Tint the parchment teal", "showTint", sub, -4, -16)
local showLogo = MakeCheck("Add the WoW Forever logo above the quest text", "showLogo", showTint, 0, -2)
local itemTint = MakeCheck("Tint the tooltips of items new to Forever", "itemTint", showLogo, 0, -2)

-- Colour swatch
local colorLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
colorLabel:SetPoint("TOPLEFT", itemTint, "BOTTOMLEFT", 4, -20)
colorLabel:SetText("Tint colour")

local swatch = CreateFrame("Button", nil, panel)
swatch:SetSize(32, 20)
swatch:SetPoint("LEFT", colorLabel, "RIGHT", 16, 0)
swatch.border = swatch:CreateTexture(nil, "BACKGROUND")
swatch.border:SetAllPoints()
swatch.border:SetColorTexture(1, 1, 1, 1)
swatch.fill = swatch:CreateTexture(nil, "ARTWORK")
swatch.fill:SetPoint("TOPLEFT", 2, -2)
swatch.fill:SetPoint("BOTTOMRIGHT", -2, 2)

local function SetTint(r, g, b)
    ns.cfg.tint[1], ns.cfg.tint[2], ns.cfg.tint[3] = r, g, b
    swatch.fill:SetColorTexture(r, g, b, 1)
    ns.Reapply()
end

swatch:SetScript("OnClick", function()
    local c = ns.cfg.tint
    local pr, pg, pb = c[1], c[2], c[3]
    local function onChange()
        SetTint(ColorPickerFrame:GetColorRGB())
    end
    local function onCancel()
        SetTint(pr, pg, pb)
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = pr, g = pg, b = pb,
            hasOpacity = false,
            swatchFunc = onChange,
            cancelFunc = onCancel,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = onChange
        ColorPickerFrame.cancelFunc = onCancel
        ColorPickerFrame:SetColorRGB(pr, pg, pb)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end)

-- Sliders (values shown and stored as percentages; config holds 0-1)
local lastAnchor = colorLabel
local function MakeSlider(label, key, min, max, scale, suffix, anchor)
    local name = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    name:SetPoint("TOPLEFT", anchor or lastAnchor, "BOTTOMLEFT", 0, -28)
    name:SetText(label)
    if not anchor then lastAnchor = name end

    local s = CreateFrame("Slider", nil, panel)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(240, 16)
    s:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -10)
    s:SetHitRectInsets(0, 0, -8, -8)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0, 0, 0, 0.6)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:GetThumbTexture():SetSize(24, 24)
    s:SetMinMaxValues(min, max)
    sliderScale[key] = scale
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)

    local value = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("LEFT", s, "RIGHT", 12, 0)

    s:SetScript("OnValueChanged", function(self, v)
        value:SetText(("%d%s"):format(v, suffix))
        if syncing then return end
        ns.cfg[key] = v / scale
        ns.Reapply()
    end)
    widgets[key] = s
    if not anchor then lastAnchor = s end
end

MakeSlider("Bottom opacity", "alpha", 0, 100, 100, "%")
MakeSlider("Top opacity", "topAlpha", 0, 100, 100, "%")
MakeSlider("Fade length (share of the parchment, from the bottom)", "height", 0, 100, 100, "%")

-- Quest name marker (quest log list and objective tracker)
local markerHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
markerHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 340, -110)
markerHeader:SetText("Quest name marker")

local marker = MakeCheck("Mark quests in log and tracker", "marker", markerHeader, -4, -8)

local symbolLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
symbolLabel:SetPoint("TOPLEFT", marker, "BOTTOMLEFT", 4, -14)
symbolLabel:SetText("Symbol")

local symbol = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
symbol:SetSize(60, 22)
symbol:SetPoint("LEFT", symbolLabel, "RIGHT", 16, 0)
symbol:SetAutoFocus(false)
symbol:SetMaxLetters(4)
symbol:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
symbol:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
symbol:SetScript("OnTextChanged", function(self, user)
    if syncing or not user then return end
    ns.cfg.markerSymbol = self:GetText()
    ns.Reapply()
end)
widgets.markerSymbol = symbol

local atStart = MakeCheck("Put the marker at the start of the name", "markerAtStart", symbolLabel, -4, -10)
local useIcon = MakeCheck("Use an icon instead of the text symbol", "markerIcon", atStart, 0, -2)
local useTint = MakeCheck("Use the tint colour", "markerUseTint", useIcon, 0, -2)

local markerColorLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
markerColorLabel:SetPoint("TOPLEFT", useTint, "BOTTOMLEFT", 4, -14)
markerColorLabel:SetText("Marker colour")

local markerSwatch = CreateFrame("Button", nil, panel)
markerSwatch:SetSize(32, 20)
markerSwatch:SetPoint("LEFT", markerColorLabel, "RIGHT", 16, 0)
markerSwatch.border = markerSwatch:CreateTexture(nil, "BACKGROUND")
markerSwatch.border:SetAllPoints()
markerSwatch.border:SetColorTexture(1, 1, 1, 1)
markerSwatch.fill = markerSwatch:CreateTexture(nil, "ARTWORK")
markerSwatch.fill:SetPoint("TOPLEFT", 2, -2)
markerSwatch.fill:SetPoint("BOTTOMRIGHT", -2, 2)

local function SetMarkerColor(r, g, b)
    local c = ns.cfg.markerColor
    c[1], c[2], c[3] = r, g, b
    markerSwatch.fill:SetColorTexture(r, g, b, 1)
    ns.Reapply()
end

markerSwatch:SetScript("OnClick", function()
    local c = ns.cfg.markerColor
    local pr, pg, pb = c[1], c[2], c[3]
    local function onChange()
        SetMarkerColor(ColorPickerFrame:GetColorRGB())
    end
    local function onCancel()
        SetMarkerColor(pr, pg, pb)
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = pr, g = pg, b = pb,
            hasOpacity = false,
            swatchFunc = onChange,
            cancelFunc = onCancel,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = onChange
        ColorPickerFrame.cancelFunc = onCancel
        ColorPickerFrame:SetColorRGB(pr, pg, pb)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end)

MakeSlider("Icon height", "markerHeight", 6, 24, 1, " px", markerColorLabel)
local iconHeightSlider = widgets.markerHeight
MakeSlider("Icon vertical position", "markerOffset", -8, 8, 1, " px", iconHeightSlider)
MakeSlider("Icon spacing from the name", "markerGap", 0, 12, 1, " px", widgets.markerOffset)


-- Objective lines: optional recolour for non-vanilla quests (left column, under the sliders)
local objHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
objHeader:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -28)
objHeader:SetText("Quest objectives")

local objTint = MakeCheck("Recolour the objectives of non-vanilla quests", "objectiveTint", objHeader, -4, -8)
local objUseTint = MakeCheck("Use the tint colour", "objectiveUseTint", objTint, 0, -2)

local objColorLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
objColorLabel:SetPoint("TOPLEFT", objUseTint, "BOTTOMLEFT", 4, -14)
objColorLabel:SetText("Objective colour")

local objSwatch = CreateFrame("Button", nil, panel)
objSwatch:SetSize(32, 20)
objSwatch:SetPoint("LEFT", objColorLabel, "RIGHT", 16, 0)
objSwatch.border = objSwatch:CreateTexture(nil, "BACKGROUND")
objSwatch.border:SetAllPoints()
objSwatch.border:SetColorTexture(1, 1, 1, 1)
objSwatch.fill = objSwatch:CreateTexture(nil, "ARTWORK")
objSwatch.fill:SetPoint("TOPLEFT", 2, -2)
objSwatch.fill:SetPoint("BOTTOMRIGHT", -2, 2)

local function SetObjectiveColor(r, g, b)
    local c = ns.cfg.objectiveColor
    c[1], c[2], c[3] = r, g, b
    objSwatch.fill:SetColorTexture(r, g, b, 1)
    ns.Reapply()
end

objSwatch:SetScript("OnClick", function()
    local c = ns.cfg.objectiveColor
    local pr, pg, pb = c[1], c[2], c[3]
    local function onChange()
        SetObjectiveColor(ColorPickerFrame:GetColorRGB())
    end
    local function onCancel()
        SetObjectiveColor(pr, pg, pb)
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = pr, g = pg, b = pb,
            hasOpacity = false,
            swatchFunc = onChange,
            cancelFunc = onCancel,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = onChange
        ColorPickerFrame.cancelFunc = onCancel
        ColorPickerFrame:SetColorRGB(pr, pg, pb)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end)

local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
reset:SetSize(140, 24)
reset:SetPoint("TOPLEFT", objColorLabel, "BOTTOMLEFT", 0, -28)
reset:SetText("Reset to defaults")

function Sync()
    syncing = true
    local c = ns.cfg
    widgets.showTint:SetChecked(c.showTint)
    widgets.showLogo:SetChecked(c.showLogo)
    widgets.itemTint:SetChecked(c.itemTint)
    widgets.marker:SetChecked(c.marker)
    widgets.markerUseTint:SetChecked(c.markerUseTint)
    widgets.markerAtStart:SetChecked(c.markerAtStart)
    widgets.markerIcon:SetChecked(c.markerIcon)
    widgets.objectiveTint:SetChecked(c.objectiveTint)
    widgets.objectiveUseTint:SetChecked(c.objectiveUseTint)
    objSwatch.fill:SetColorTexture(c.objectiveColor[1], c.objectiveColor[2], c.objectiveColor[3], 1)
    widgets.markerSymbol:SetText(c.markerSymbol)
    widgets.markerSymbol:SetCursorPosition(0)
    markerSwatch.fill:SetColorTexture(c.markerColor[1], c.markerColor[2], c.markerColor[3], 1)
    swatch.fill:SetColorTexture(c.tint[1], c.tint[2], c.tint[3], 1)
    for _, key in ipairs({ "alpha", "topAlpha", "height", "markerHeight", "markerOffset", "markerGap" }) do
        widgets[key]:SetValue(math.floor(c[key] * sliderScale[key] + 0.5))
    end
    syncing = false
end

reset:SetScript("OnClick", function()
    for k, v in pairs(ns.defaults) do
        if type(v) == "table" then
            for i, x in ipairs(v) do ns.cfg[k][i] = x end
        else
            ns.cfg[k] = v
        end
    end
    Sync()
    ns.Reapply()
end)

panel:SetScript("OnShow", Sync)

local category
if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

function ns.OpenOptions()
    if Settings and Settings.OpenToCategory and category then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
