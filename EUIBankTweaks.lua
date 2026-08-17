local ADDON_NAME = ...

-------------------------------------------------------------------------------
-- EUI Bank Tweaks
-- Author: neXi0r
-- https://github.com/neXi0r/EUIBankTweaks
--
-- Extra sizing and layout controls for EllesmereUI's Bank / Warband Bank.
-------------------------------------------------------------------------------

local STOCK_SLOT_SIZE = 34
local STOCK_SPACING = 4
local STOCK_COLUMNS = 14

local DEFAULTS = {
    enabled = true,
    warbandOnly = false,
    slotSize = 30,
    columns = 16,
    spacing = 3,
    bankScale = 1.00,  -- multiplier on top of EUI Bags Window Scale
    textScale = 0.90,
}

local DB
local hooked = false
local optionsFrame
local optionsUpdating = false
local headerFrames = {}
local pendingToken = 0
local warnedCompatibility = false
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

local function CopyDefaults()
    if type(EUIBankTweaksDB) ~= "table" then
        EUIBankTweaksDB = {}
    end
    for k, v in pairs(DEFAULTS) do
        if EUIBankTweaksDB[k] == nil then
            EUIBankTweaksDB[k] = v
        end
    end
    DB = EUIBankTweaksDB
end

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function RoundToStep(v, step)
    return math.floor((v / step) + 0.5) * step
end

local function GetBank()
    return _G.EUI_BankFrame
end

local function GetEUIBagProfile()
    local eui = _G.EllesmereUI
    if eui and eui._bagsDB and eui._bagsDB.profile then
        return eui._bagsDB.profile
    end
end

local function GetEUIBaseScale()
    local p = GetEUIBagProfile()
    return (p and p.bagScale) or 1
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff0cd29fEUI Bank Tweaks:|r " .. tostring(msg))
end

local function IsWarbandView(bank)
    if bank and bank.IsWarbandView then
        local ok, result = pcall(bank.IsWarbandView, bank)
        if ok then return result and true or false end
    end
    return false
end

local function ShouldApply(bank)
    if not DB or DB.enabled == false then return false end
    if DB.warbandOnly and not IsWarbandView(bank) then return false end
    return true
end

local function BankInternalsReady(bank)
    return bank
        and type(bank._layout) == "table"
        and type(bank._bankSlots) == "table"
        and bank._scrollChild
        and bank._scrollFrame
end

local function WarnCompatibilityOnce()
    if warnedCompatibility then return end
    warnedCompatibility = true
    Print("EUI bank layout not found. This addon may need an update.")
end

-------------------------------------------------------------------------------
-- Text scaling
-------------------------------------------------------------------------------

local function ApplySlotTextScale(btn, scale)
    if not btn then return end

    local eui = _G.EllesmereUI
    local p = GetEUIBagProfile() or {}
    local fontPath = (eui and eui.GetFontPath and eui.GetFontPath("bags")) or "Fonts\\FRIZQT__.TTF"

    local countSize = math.max(7, math.floor(((p.bagCountFontSize or 11) * scale) + 0.5))
    local ilvlSize = math.max(7, math.floor(((p.itemlevelFontSize or 12) * scale) + 0.5))
    local bindSize = math.max(7, math.floor(((p.bagBindTypeFontSize or 11) * scale) + 0.5))

    if btn.Count then
        if eui and eui.ApplyIconTextFont then
            eui.ApplyIconTextFont(btn.Count, fontPath, countSize, "bags")
        else
            btn.Count:SetFont(fontPath, countSize, "OUTLINE")
        end
    end

    local flags = "OUTLINE"
    if eui and eui.SlugFlag then
        flags = eui.SlugFlag("OUTLINE, SLUG") or flags
    end

    if btn.ItemLevelText then
        btn.ItemLevelText:SetFont(fontPath, ilvlSize, flags)
    end
    if btn.BindTypeText then
        btn.BindTypeText:SetFont(fontPath, bindSize, flags)
    end
end

local function RestoreStockSlotAppearance(bank)
    if not bank or type(bank._bankSlots) ~= "table" then return end
    for _, btn in ipairs(bank._bankSlots) do
        if btn then
            local parent = btn:GetParent()
            if parent then parent:SetSize(STOCK_SLOT_SIZE, STOCK_SLOT_SIZE) end
            btn:ClearAllPoints()
            if parent then btn:SetAllPoints(parent) end
            ApplySlotTextScale(btn, 1)
        end
    end
    bank:SetScale(GetEUIBaseScale())
end

-------------------------------------------------------------------------------
-- Header lookup
-- EUI doesn't expose its header table, so cache the headers after finding them.
-------------------------------------------------------------------------------

local function FindHeaderFrame(child, entry)
    local idx = entry.headerIdx
    local cached = idx and headerFrames[idx]
    if cached and cached:GetParent() == child then
        return cached
    end

    local children = { child:GetChildren() }
    for _, frame in ipairs(children) do
        if frame and frame.GetNumChildren and frame:GetNumChildren() == 0 then
            local h = frame:GetHeight() or 0
            if math.abs(h - 20) < 1.5 then
                local point, rel, _, x, y = frame:GetPoint(1)
                if point == "TOPLEFT" and rel == child
                    and math.abs((x or 0) - (entry.x or 0)) < 1.5
                    and math.abs((y or 0) - (entry.y or 0)) < 1.5 then
                    if idx then headerFrames[idx] = frame end
                    return frame
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Custom layout
-------------------------------------------------------------------------------

local function GetSidebarWidth(bank)
    local sf = bank and bank._scrollFrame
    if sf then
        local _, rel, _, x = sf:GetPoint(1)
        if rel == bank and type(x) == "number" and x >= 20 and x <= 260 then
            return x
        end
    end
    return 160
end

local function FinishGroup(curY, itemCount, columns, pitch)
    if itemCount <= 0 then return curY end
    local rows = math.ceil(itemCount / columns)
    return curY - (rows * pitch) - 6
end

local function ApplyCustomLayout()
    local bank = GetBank()
    if not bank or not bank:IsShown() then return end

    if InCombatLockdown and InCombatLockdown() then
        return
    end

    if not BankInternalsReady(bank) then
        WarnCompatibilityOnce()
        return
    end

    if not ShouldApply(bank) then
        RestoreStockSlotAppearance(bank)
        return
    end

    local layout = bank._layout
    local slots = bank._bankSlots
    local child = bank._scrollChild
    local columns = Clamp(math.floor((DB.columns or DEFAULTS.columns) + 0.5), 8, 24)
    local slotSize = Clamp(math.floor((DB.slotSize or DEFAULTS.slotSize) + 0.5), 20, 44)
    local spacing = Clamp(math.floor((DB.spacing or DEFAULTS.spacing) + 0.5), 0, 10)
    local textScale = Clamp(DB.textScale or DEFAULTS.textScale, 0.60, 1.30)
    local pitch = slotSize + spacing
    local startX = bank._layoutStartX or 15
    local gridW = columns * pitch

    -- Keep EUI's sidebar width.
    local sidebarW = GetSidebarWidth(bank)
    local GRID_PAD_TOTAL = 20
    local SCROLLBAR_HIT_W = 16
    local EXTRA_W = 2
    bank:SetWidth(sidebarW + gridW + GRID_PAD_TOTAL + SCROLLBAR_HIT_W + EXTRA_W)
    child:SetWidth(gridW + GRID_PAD_TOTAL + SCROLLBAR_HIT_W)

    -- Bank-only scale.
    bank:SetScale(GetEUIBaseScale() * Clamp(DB.bankScale or 1, 0.65, 1.35))

    local curY = -6
    local currentGroupCount = 0
    local haveGroup = false
    local slotIdx = 0

    for _, entry in ipairs(layout) do
        if entry.isHeader then
            if haveGroup then
                curY = FinishGroup(curY, currentGroupCount, columns, pitch)
            end

            local hdr = FindHeaderFrame(child, entry)
            if hdr then
                hdr:ClearAllPoints()
                hdr:SetPoint("TOPLEFT", child, "TOPLEFT", startX, curY)
                hdr:SetWidth(gridW)
            end

            curY = curY - 22
            currentGroupCount = 0
            haveGroup = true
        else
            slotIdx = slotIdx + 1
            local btn = slots[slotIdx]
            if btn then
                local parent = btn:GetParent()
                if parent then
                    local col = currentGroupCount % columns
                    local row = math.floor(currentGroupCount / columns)
                    parent:SetSize(slotSize, slotSize)
                    parent:ClearAllPoints()
                    parent:SetPoint("TOPLEFT", child, "TOPLEFT",
                        startX + (col * pitch),
                        curY - (row * pitch))

                    btn:ClearAllPoints()
                    btn:SetAllPoints(parent)
                    ApplySlotTextScale(btn, textScale)
                end
            end
            currentGroupCount = currentGroupCount + 1
        end
    end

    if haveGroup then
        curY = FinishGroup(curY, currentGroupCount, columns, pitch)
    end

    child:SetHeight(math.max(1, math.abs(curY) + 10))

    local sf = bank._scrollFrame
    if sf then
        local range = sf:GetVerticalScrollRange() or 0
        if sf:GetVerticalScroll() > range then
            sf:SetVerticalScroll(range)
        end
    end
    if bank._updateThumb then
        bank._updateThumb()
    end
end

local function ScheduleApply()
    pendingToken = pendingToken + 1
    local token = pendingToken

    local delays = { 0, 0.03, 0.10, 0.25 }
    for _, delay in ipairs(delays) do
        C_Timer.After(delay, function()
            if token ~= pendingToken then return end
            ApplyCustomLayout()
        end)
    end
end

local function RefreshBankFromEUI()
    local bank = GetBank()
    if bank and bank:IsShown() and bank.RefreshBank then
        bank:RefreshBank()
    else
        ScheduleApply()
    end
end

-------------------------------------------------------------------------------
-- EUI hooks
-------------------------------------------------------------------------------

local function HookEUIBank()
    if hooked then return true end
    local bank = GetBank()
    if not bank or type(bank.RefreshBank) ~= "function" then return false end

    hooksecurefunc(bank, "RefreshBank", function()
        ScheduleApply()
    end)

    bank:HookScript("OnShow", function()
        ScheduleApply()
    end)

    hooked = true
    return true
end

-------------------------------------------------------------------------------
-- UI helpers
-------------------------------------------------------------------------------

local function MakeText(parent, size, text, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size, "")
    fs:SetText(text or "")
    fs:SetTextColor(r or 1, g or 1, b or 1)
    return fs
end

local function MakeButton(parent, text, width, height, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 100, height or 26)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.09, 0.10, 0.95)
    b._bg = bg

    local border = b:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.24, 0.26, 0.28, 1)
    b._border = border

    local inset = b:CreateTexture(nil, "ARTWORK")
    inset:SetPoint("TOPLEFT", 0, 0)
    inset:SetPoint("BOTTOMRIGHT", 0, 0)
    inset:SetColorTexture(0.08, 0.09, 0.10, 1)

    local label = MakeText(b, 11, text, 0.90, 0.90, 0.90)
    label:SetPoint("CENTER")
    b._label = label

    b:SetScript("OnEnter", function(self)
        self._bg:SetColorTexture(0.13, 0.15, 0.16, 0.98)
        self._label:SetTextColor(1, 1, 1)
    end)
    b:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(0.08, 0.09, 0.10, 0.95)
        self._label:SetTextColor(0.90, 0.90, 0.90)
    end)
    b:SetScript("OnClick", onClick)
    return b
end

local function MakeCheckbox(parent, labelText, y, getter, setter)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(360, 24)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, y)

    local box = CreateFrame("Frame", nil, row)
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.05, 0.06, 1)
    local border = box:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.35, 0.38, 0.40, 1)
    local check = box:CreateTexture(nil, "ARTWORK")
    check:SetPoint("TOPLEFT", 3, -3)
    check:SetPoint("BOTTOMRIGHT", -3, 3)
    check:SetColorTexture(0.047, 0.824, 0.616, 1)

    local label = MakeText(row, 12, labelText, 0.88, 0.88, 0.88)
    label:SetPoint("LEFT", box, "RIGHT", 9, 0)

    local function Refresh()
        check:SetShown(getter() and true or false)
    end

    row:SetScript("OnClick", function()
        setter(not getter())
        Refresh()
    end)
    row:SetScript("OnEnter", function() label:SetTextColor(1, 1, 1) end)
    row:SetScript("OnLeave", function() label:SetTextColor(0.88, 0.88, 0.88) end)
    row.Refresh = Refresh
    Refresh()
    return row
end

local function MakeSlider(parent, labelText, y, minVal, maxVal, step, getter, setter, formatter)
    local label = MakeText(parent, 11, labelText, 0.80, 0.82, 0.84)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, y)

    local valueText = MakeText(parent, 11, "", 0.047, 0.824, 0.616)
    valueText:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -24, y)
    valueText:SetJustifyH("RIGHT")

    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(330, 18)
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -7)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(4)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetColorTexture(0.16, 0.18, 0.19, 1)

    slider:SetThumbTexture(WHITE8X8)
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(8, 18)
    thumb:SetColorTexture(0.047, 0.824, 0.616, 1)

    local minus = MakeButton(parent, "-", 28, 22, function()
        slider:SetValue(Clamp(slider:GetValue() - step, minVal, maxVal))
    end)
    minus:SetPoint("LEFT", slider, "RIGHT", 8, 0)

    local plus = MakeButton(parent, "+", 28, 22, function()
        slider:SetValue(Clamp(slider:GetValue() + step, minVal, maxVal))
    end)
    plus:SetPoint("LEFT", minus, "RIGHT", 5, 0)

    local function Format(v)
        if formatter then return formatter(v) end
        return tostring(v)
    end

    slider:SetScript("OnValueChanged", function(self, value)
        local rounded = RoundToStep(value, step)
        valueText:SetText(Format(rounded))
        if optionsUpdating then return end
        setter(rounded)
    end)

    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(Clamp(self:GetValue() + (delta > 0 and step or -step), minVal, maxVal))
    end)

    slider.Refresh = function()
        optionsUpdating = true
        slider:SetValue(getter())
        valueText:SetText(Format(getter()))
        optionsUpdating = false
    end
    slider.Refresh()
    return slider
end

-------------------------------------------------------------------------------
-- Options window
-------------------------------------------------------------------------------

local function BuildOptionsFrame()
    if optionsFrame then return optionsFrame end

    local f = CreateFrame("Frame", "EUIBankTweaksOptionsFrame", UIParent)
    f:SetSize(470, 535)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local shadow = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    shadow:SetPoint("TOPLEFT", -4, 4)
    shadow:SetPoint("BOTTOMRIGHT", 4, -4)
    shadow:SetColorTexture(0, 0, 0, 0.8)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.035, 0.043, 0.050, 0.98)

    local top = f:CreateTexture(nil, "ARTWORK")
    top:SetPoint("TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", 0, 0)
    top:SetHeight(44)
    top:SetColorTexture(0.055, 0.065, 0.072, 1)

    local accent = f:CreateTexture(nil, "ARTWORK", nil, 2)
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("TOPRIGHT", 0, 0)
    accent:SetHeight(2)
    accent:SetColorTexture(0.047, 0.824, 0.616, 1)

    local title = MakeText(f, 15, "EUI Bank Tweaks", 1, 1, 1)
    title:SetPoint("TOPLEFT", 16, -13)

    local version = MakeText(f, 10, "v1.0.0", 0.45, 0.48, 0.50)
    version:SetPoint("LEFT", title, "RIGHT", 8, 0)

    local close = MakeButton(f, "x", 26, 24, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -10, -10)

    local subtitle = MakeText(f, 11,
        "Bank layout options for EllesmereUI.",
        0.62, 0.65, 0.68)
    subtitle:SetPoint("TOPLEFT", 24, -60)

    local enableRow = MakeCheckbox(f, "Enable custom bank layout", -88,
        function() return DB.enabled ~= false end,
        function(v)
            DB.enabled = v
            RefreshBankFromEUI()
        end)

    local warbandRow = MakeCheckbox(f, "Apply only to Warband Bank views", -116,
        function() return DB.warbandOnly == true end,
        function(v)
            DB.warbandOnly = v
            RefreshBankFromEUI()
        end)

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 24, -148)
    divider:SetPoint("TOPRIGHT", -24, -148)
    divider:SetHeight(1)
    divider:SetColorTexture(1, 1, 1, 0.08)

    local sliders = {}
    sliders[#sliders + 1] = MakeSlider(f, "Item slot size", -166, 20, 44, 1,
        function() return DB.slotSize end,
        function(v) DB.slotSize = v; ScheduleApply() end,
        function(v) return string.format("%d px", v) end)

    sliders[#sliders + 1] = MakeSlider(f, "Columns", -230, 8, 24, 1,
        function() return DB.columns end,
        function(v) DB.columns = v; ScheduleApply() end,
        function(v) return string.format("%d", v) end)

    sliders[#sliders + 1] = MakeSlider(f, "Spacing", -294, 0, 10, 1,
        function() return DB.spacing end,
        function(v) DB.spacing = v; ScheduleApply() end,
        function(v) return string.format("%d px", v) end)

    sliders[#sliders + 1] = MakeSlider(f, "Bank scale", -358, 0.65, 1.35, 0.05,
        function() return DB.bankScale end,
        function(v) DB.bankScale = v; ScheduleApply() end,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)

    sliders[#sliders + 1] = MakeSlider(f, "Item text scale", -422, 0.60, 1.30, 0.05,
        function() return DB.textScale end,
        function(v) DB.textScale = v; ScheduleApply() end,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)

    local compact = MakeButton(f, "Compact", 110, 28, function()
        DB.enabled = true
        DB.slotSize = 30
        DB.columns = 16
        DB.spacing = 3
        DB.bankScale = 1.00
        DB.textScale = 0.90
        f:RefreshControls()
        RefreshBankFromEUI()
    end)
    compact:SetPoint("BOTTOMLEFT", 24, 20)

    local dense = MakeButton(f, "Dense", 110, 28, function()
        DB.enabled = true
        DB.slotSize = 28
        DB.columns = 18
        DB.spacing = 2
        DB.bankScale = 1.00
        DB.textScale = 0.85
        f:RefreshControls()
        RefreshBankFromEUI()
    end)
    dense:SetPoint("LEFT", compact, "RIGHT", 8, 0)

    local stock = MakeButton(f, "EUI Default", 120, 28, function()
        DB.enabled = true
        DB.slotSize = STOCK_SLOT_SIZE
        DB.columns = STOCK_COLUMNS
        DB.spacing = STOCK_SPACING
        DB.bankScale = 1.00
        DB.textScale = 1.00
        f:RefreshControls()
        RefreshBankFromEUI()
    end)
    stock:SetPoint("LEFT", dense, "RIGHT", 8, 0)

    local hint = MakeText(f, 10, "Open the bank to preview changes.", 0.48, 0.52, 0.54)
    hint:SetPoint("BOTTOMRIGHT", -24, 56)

    function f:RefreshControls()
        enableRow:Refresh()
        warbandRow:Refresh()
        for _, slider in ipairs(sliders) do slider:Refresh() end
    end

    f:SetScript("OnShow", function(self)
        self:RefreshControls()
        if not HookEUIBank() then
            C_Timer.After(0.5, HookEUIBank)
        end
    end)

    table.insert(UISpecialFrames, f:GetName())
    f:Hide()
    optionsFrame = f
    return f
end

local function ToggleOptions()
    local f = BuildOptionsFrame()
    if f:IsShown() then f:Hide() else f:Show() end
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

SLASH_EUIBANKTWEAKS1 = "/ebt"
SlashCmdList.EUIBANKTWEAKS = function()
    ToggleOptions()
end

-------------------------------------------------------------------------------
-- Startup
-------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        CopyDefaults()
        BuildOptionsFrame()
        return
    end

    if event == "PLAYER_LOGIN" then
        CopyDefaults()
        if not HookEUIBank() then
            C_Timer.After(1, function()
                if not HookEUIBank() then
                    WarnCompatibilityOnce()
                end
            end)
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        ScheduleApply()
    end
end)
