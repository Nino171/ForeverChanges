local ADDON, ns = ...

local panel = CreateFrame("Frame")
panel.name = "Forever Quest Tint"

local syncing = false
local widgets = {}

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Forever Quest Tint")

local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
sub:SetText("Tints the quest text background teal for quests that were not in original Classic.\nOpen a non-vanilla quest in the Map & Quest Log to preview changes.")
sub:SetJustifyH("LEFT")

-- Enabled checkbox
local enabled = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
enabled:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -4, -16)
enabled.text = enabled:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
enabled.text:SetPoint("LEFT", enabled, "RIGHT", 2, 0)
enabled.text:SetText("Enable tint")
enabled:SetScript("OnClick", function(self)
    if syncing then return end
    ns.cfg.enabled = self:GetChecked() and true or false
    ns.Reapply()
end)
widgets.enabled = enabled

-- Colour swatch
local colorLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
colorLabel:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 4, -20)
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
local function MakeSlider(label, key)
    local name = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    name:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -28)
    name:SetText(label)
    lastAnchor = name

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
    s:SetMinMaxValues(0, 100)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)

    local value = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("LEFT", s, "RIGHT", 12, 0)

    s:SetScript("OnValueChanged", function(self, v)
        value:SetText(("%d%%"):format(v))
        if syncing then return end
        ns.cfg[key] = v / 100
        ns.Reapply()
    end)
    widgets[key] = s
    lastAnchor = s
end

MakeSlider("Bottom opacity", "alpha")
MakeSlider("Top opacity", "topAlpha")
MakeSlider("Fade length (share of the parchment, from the bottom)", "height")

local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
reset:SetSize(140, 24)
reset:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -28)
reset:SetText("Reset to defaults")

local function Sync()
    syncing = true
    local c = ns.cfg
    widgets.enabled:SetChecked(c.enabled)
    swatch.fill:SetColorTexture(c.tint[1], c.tint[2], c.tint[3], 1)
    for _, key in ipairs({ "alpha", "topAlpha", "height" }) do
        widgets[key]:SetValue(math.floor(c[key] * 100 + 0.5))
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
