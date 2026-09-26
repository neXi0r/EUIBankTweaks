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

local SLOT_MIN, SLOT_MAX = 18, 50
local COL_MIN, COL_MAX = 6, 30
local SPACE_MIN, SPACE_MAX = 0, 12
local SCALE_MIN, SCALE_MAX = 0.50, 1.50
local TEXT_MIN, TEXT_MAX = 0.50, 1.50
local MIN_BANK_WIDTH = 420

local DEFAULTS = {
    enabled = true,
    warbandOnly = false,
    slotSize = 30,
    columns = 16,
    spacingX = 3,
    spacingY = 3,
    bankScale = 1.00,  -- multiplier on top of EUI Bags Window Scale
    textScale = 0.90,
}

local BUILTIN_PRESETS = {
    ["EUI Default"] = { slotSize = STOCK_SLOT_SIZE, columns = STOCK_COLUMNS, spacingX = STOCK_SPACING, spacingY = STOCK_SPACING, bankScale = 1.00, textScale = 1.00 },
    ["Compact"]     = { slotSize = 30, columns = 16, spacingX = 3, spacingY = 3, bankScale = 1.00, textScale = 0.90 },
    ["Dense"]       = { slotSize = 28, columns = 18, spacingX = 2, spacingY = 2, bankScale = 1.00, textScale = 0.85 },
}
local BUILTIN_ORDER = { "EUI Default", "Compact", "Dense" }
local MAX_CUSTOM_PRESETS = 10
local PRESET_NAME_MAX = 24

local DB
local hooked = false
local optionsFrame
local optionsUpdating = false
local headerFrames = {}
local pendingToken = 0
local warnedCompatibility = false
local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local ADDON_VERSION = "1.1.0"

-- Per-button state kept separately from EUI item buttons.
local textSignatureByButton = setmetatable({}, { __mode = "k" })
local batchHooked = setmetatable({}, { __mode = "k" })
local styledPoolCount = setmetatable({}, { __mode = "k" })

local function CopyDefaults()
    if type(EUIBankTweaksDB) ~= "table" then
        EUIBankTweaksDB = {}
    end

    -- 1.0.0 used one spacing value for both axes.
    if EUIBankTweaksDB.spacingX == nil then
        EUIBankTweaksDB.spacingX = EUIBankTweaksDB.spacing or DEFAULTS.spacingX
    end
    if EUIBankTweaksDB.spacingY == nil then
        EUIBankTweaksDB.spacingY = EUIBankTweaksDB.spacing or DEFAULTS.spacingY
    end

    for k, v in pairs(DEFAULTS) do
        if EUIBankTweaksDB[k] == nil then
            EUIBankTweaksDB[k] = v
        end
    end

    if type(EUIBankTweaksDB.presets) ~= "table" then
        EUIBankTweaksDB.presets = {}
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

local function Trim(text)
    return tostring(text or ""):match("^%s*(.-)%s*$")
end

local function CaptureLayoutSettings()
    return {
        slotSize = Clamp(math.floor((DB.slotSize or DEFAULTS.slotSize) + 0.5), SLOT_MIN, SLOT_MAX),
        columns = Clamp(math.floor((DB.columns or DEFAULTS.columns) + 0.5), COL_MIN, COL_MAX),
        spacingX = Clamp(math.floor((DB.spacingX or DEFAULTS.spacingX) + 0.5), SPACE_MIN, SPACE_MAX),
        spacingY = Clamp(math.floor((DB.spacingY or DEFAULTS.spacingY) + 0.5), SPACE_MIN, SPACE_MAX),
        bankScale = Clamp(DB.bankScale or DEFAULTS.bankScale, SCALE_MIN, SCALE_MAX),
        textScale = Clamp(DB.textScale or DEFAULTS.textScale, TEXT_MIN, TEXT_MAX),
    }
end

local function ApplyPresetValues(preset)
    if type(preset) ~= "table" then return end
    DB.enabled = true
    DB.slotSize = Clamp(math.floor((preset.slotSize or DEFAULTS.slotSize) + 0.5), SLOT_MIN, SLOT_MAX)
    DB.columns = Clamp(math.floor((preset.columns or DEFAULTS.columns) + 0.5), COL_MIN, COL_MAX)
    DB.spacingX = Clamp(math.floor((preset.spacingX or preset.spacing or DEFAULTS.spacingX) + 0.5), SPACE_MIN, SPACE_MAX)
    DB.spacingY = Clamp(math.floor((preset.spacingY or preset.spacing or DEFAULTS.spacingY) + 0.5), SPACE_MIN, SPACE_MAX)
    DB.bankScale = Clamp(preset.bankScale or DEFAULTS.bankScale, SCALE_MIN, SCALE_MAX)
    DB.textScale = Clamp(preset.textScale or DEFAULTS.textScale, TEXT_MIN, TEXT_MAX)
end

local function LayoutMatchesPreset(preset)
    if type(preset) ~= "table" then return false end
    local cur = CaptureLayoutSettings()
    return cur.slotSize == preset.slotSize
        and cur.columns == preset.columns
        and cur.spacingX == (preset.spacingX or preset.spacing)
        and cur.spacingY == (preset.spacingY or preset.spacing)
        and math.abs(cur.bankScale - (preset.bankScale or 1)) < 0.001
        and math.abs(cur.textScale - (preset.textScale or 1)) < 0.001
end

local function FindCustomPresetByName(name, skipIndex)
    local wanted = string.lower(Trim(name))
    for i, preset in ipairs(DB.presets or {}) do
        if i ~= skipIndex and type(preset) == "table"
            and string.lower(Trim(preset.name)) == wanted then
            return i, preset
        end
    end
end

local function IsBuiltinPresetName(name)
    local wanted = string.lower(Trim(name))
    for _, builtinName in ipairs(BUILTIN_ORDER) do
        if string.lower(builtinName) == wanted then return true end
    end
    return false
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

local function ApplySlotTextScale(btn, scale, force)
    if not btn then return end

    local eui = _G.EllesmereUI
    local p = GetEUIBagProfile() or {}
    local fontPath = (eui and eui.GetFontPath and eui.GetFontPath("bags")) or "Fonts\\FRIZQT__.TTF"

    local countSize = math.max(6, math.floor(((p.bagCountFontSize or 11) * scale) + 0.5))
    local ilvlSize = math.max(6, math.floor(((p.itemlevelFontSize or 12) * scale) + 0.5))
    local bindSize = math.max(6, math.floor(((p.bagBindTypeFontSize or 11) * scale) + 0.5))

    local flags = "OUTLINE"
    if eui and eui.SlugFlag then
        flags = eui.SlugFlag("OUTLINE, SLUG") or flags
    end

    local sig = table.concat({ fontPath, countSize, ilvlSize, bindSize, flags }, "|")
    if not force and textSignatureByButton[btn] == sig then return end
    textSignatureByButton[btn] = sig

    if btn.Count then
        if eui and eui.ApplyIconTextFont then
            eui.ApplyIconTextFont(btn.Count, fontPath, countSize, "bags")
        else
            btn.Count:SetFont(fontPath, countSize, "OUTLINE")
        end
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
            if parent then
                local w, h = parent:GetSize()
                if math.abs((w or 0) - STOCK_SLOT_SIZE) > 0.01
                    or math.abs((h or 0) - STOCK_SLOT_SIZE) > 0.01 then
                    parent:SetSize(STOCK_SLOT_SIZE, STOCK_SLOT_SIZE)
                end
            end
            ApplySlotTextScale(btn, 1, true)
        end
    end

    styledPoolCount[bank] = #bank._bankSlots
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

local function NearlyEqual(a, b)
    return math.abs((a or 0) - (b or 0)) < 0.5
end

local function FrameNeedsPoint(frame, relativeTo, x, y)
    if not frame or not frame.GetPoint then return false end
    if frame.GetNumPoints and frame:GetNumPoints() ~= 1 then return true end

    local point, rel, relPoint, curX, curY = frame:GetPoint(1)
    return point ~= "TOPLEFT"
        or rel ~= relativeTo
        or (relPoint and relPoint ~= "TOPLEFT")
        or not NearlyEqual(curX, x)
        or not NearlyEqual(curY, y)
end

local function PositionFrame(frame, relativeTo, x, y)
    if not frame or not FrameNeedsPoint(frame, relativeTo, x, y) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", relativeTo, "TOPLEFT", x, y)
end

local function StyleSlotRange(bank, firstIndex, lastIndex, forceText)
    if not bank or not ShouldApply(bank) or type(bank._bankSlots) ~= "table" then return end

    local slots = bank._bankSlots
    local slotSize = Clamp(math.floor((DB.slotSize or DEFAULTS.slotSize) + 0.5), SLOT_MIN, SLOT_MAX)
    local textScale = Clamp(DB.textScale or DEFAULTS.textScale, TEXT_MIN, TEXT_MAX)
    local first = math.max(1, firstIndex or 1)
    local last = math.min(lastIndex or #slots, #slots)

    for i = first, last do
        local btn = slots[i]
        if btn then
            local parent = btn:GetParent()
            if parent then
                local w, h = parent:GetSize()
                if math.abs((w or 0) - slotSize) > 0.01
                    or math.abs((h or 0) - slotSize) > 0.01 then
                    parent:SetSize(slotSize, slotSize)
                end
            end
            ApplySlotTextScale(btn, textScale, forceText)
        end
    end
end

local function StyleNewSlots(bank)
    if not bank or type(bank._bankSlots) ~= "table" then return end
    local count = #bank._bankSlots
    local done = styledPoolCount[bank] or 0
    if count > done then
        StyleSlotRange(bank, done + 1, count, false)
        styledPoolCount[bank] = count
    end
end

local function ApplyCustomLayout(forceText)
    local bank = GetBank()
    if not bank or not bank:IsShown() then return end

    if InCombatLockdown and InCombatLockdown() then
        return
    end

    if not BankInternalsReady(bank) then
        return
    end

    if not ShouldApply(bank) then
        RestoreStockSlotAppearance(bank)
        return
    end

    local layout = bank._layout
    local slots = bank._bankSlots
    local child = bank._scrollChild
    local columns = Clamp(math.floor((DB.columns or DEFAULTS.columns) + 0.5), COL_MIN, COL_MAX)
    local slotSize = Clamp(math.floor((DB.slotSize or DEFAULTS.slotSize) + 0.5), SLOT_MIN, SLOT_MAX)
    local spacingX = Clamp(math.floor((DB.spacingX or DEFAULTS.spacingX) + 0.5), SPACE_MIN, SPACE_MAX)
    local spacingY = Clamp(math.floor((DB.spacingY or DEFAULTS.spacingY) + 0.5), SPACE_MIN, SPACE_MAX)
    local textScale = Clamp(DB.textScale or DEFAULTS.textScale, TEXT_MIN, TEXT_MAX)
    local pitchX = slotSize + spacingX
    local pitchY = slotSize + spacingY
    local startX = bank._layoutStartX or 15
    local gridW = columns * pitchX

    -- Match EUI's own width formula, replacing only the grid width.
    local sidebarW = GetSidebarWidth(bank)
    local GRID_PAD_TOTAL = 20
    local SCROLLBAR_HIT_W = 16
    local EXTRA_W = 2
    bank:SetWidth(math.max(MIN_BANK_WIDTH, sidebarW + gridW + GRID_PAD_TOTAL + SCROLLBAR_HIT_W + EXTRA_W))
    child:SetWidth(gridW + GRID_PAD_TOTAL + SCROLLBAR_HIT_W)
    bank:SetScale(GetEUIBaseScale() * Clamp(DB.bankScale or 1, SCALE_MIN, SCALE_MAX))

    local curY = -6
    local currentGroupCount = 0
    local slotIdx = 0

    for _, entry in ipairs(layout) do
        if entry.isHeader then
            if currentGroupCount > 0 then
                curY = FinishGroup(curY, currentGroupCount, columns, pitchY)
                currentGroupCount = 0
            end

            -- Update headers already drawn by EUI.
            local hdr = FindHeaderFrame(child, entry)
            local depth = tonumber(entry.depth) or 0
            local indent = depth * 12
            local headerX = startX + indent
            local headerW = math.max(1, gridW - indent)

            entry.x = headerX
            entry.y = curY
            entry.w = headerW

            if hdr and hdr:IsShown() then
                PositionFrame(hdr, child, entry.x, entry.y)
                if not NearlyEqual(hdr:GetWidth(), entry.w) then
                    hdr:SetWidth(entry.w)
                end
            end

            curY = curY - (depth > 0 and 18 or 22)
        else
            slotIdx = slotIdx + 1
            local col = currentGroupCount % columns
            local row = math.floor(currentGroupCount / columns)
            local x = startX + (col * pitchX)
            local y = curY - (row * pitchY)

            -- Later EUI render batches use these coordinates too.
            entry.x = x
            entry.y = y

            -- Only move slots EUI has already assigned to this entry.
            local btn = slots[slotIdx]
            if btn then
                local parent = btn:GetParent()
                if parent
                    and parent:GetID() == entry.bagID
                    and btn:GetID() == entry.slot then
                    local w, h = parent:GetSize()
                    if math.abs((w or 0) - slotSize) > 0.01
                        or math.abs((h or 0) - slotSize) > 0.01 then
                        parent:SetSize(slotSize, slotSize)
                    end
                    PositionFrame(parent, child, x, y)
                    ApplySlotTextScale(btn, textScale, forceText)
                end
            end

            currentGroupCount = currentGroupCount + 1
        end
    end

    if currentGroupCount > 0 then
        curY = FinishGroup(curY, currentGroupCount, columns, pitchY)
    end

    child:SetHeight(math.max(1, math.abs(curY) + 10))
    bank._layoutGridW = gridW

    -- Keep pooled slot size/text ready for later EUI batches.
    StyleSlotRange(bank, 1, #slots, forceText)
    styledPoolCount[bank] = #slots

    local sf = bank._scrollFrame
    if sf then
        local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
        if sf:GetVerticalScroll() > maxScroll then
            sf:SetVerticalScroll(maxScroll)
        end
    end
    if bank._updateThumb then
        bank._updateThumb()
    end
end

local function ScheduleApply()
    pendingToken = pendingToken + 1
    local token = pendingToken

    -- Extra settle passes for settings changes and bank open.
    C_Timer.After(0, function()
        if token ~= pendingToken then return end
        ApplyCustomLayout()
    end)

    C_Timer.After(0.10, function()
        if token ~= pendingToken then return end
        ApplyCustomLayout()
    end)
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

local batchWatchFrame
local batchWatchBank
local batchWatchQuietFrames = 0

local function EnsureBatchHook(bank)
    local batch = bank and bank._batchFrame
    if not batch or batchHooked[batch] then return end

    batchHooked[batch] = true
    batch:HookScript("OnUpdate", function()
        if bank:IsShown() and ShouldApply(bank) then
            -- Style slots created by the current EUI batch.
            StyleNewSlots(bank)
        end
    end)
end

local function StartBatchWatcher(bank)
    if not bank then return end

    if not batchWatchFrame then
        batchWatchFrame = CreateFrame("Frame")
    end

    batchWatchBank = bank
    batchWatchQuietFrames = 0

    batchWatchFrame:SetScript("OnUpdate", function(self)
        local watched = batchWatchBank
        if not watched or not watched:IsShown() then
            self:SetScript("OnUpdate", nil)
            return
        end

        EnsureBatchHook(watched)
        StyleNewSlots(watched)

        local batch = watched._batchFrame
        local batchActive = batch and batch:GetScript("OnUpdate") ~= nil
        if batchActive then
            batchWatchQuietFrames = 0
        else
            batchWatchQuietFrames = batchWatchQuietFrames + 1
        end

        -- Catch the final EUI batch before stopping.
        if batchWatchQuietFrames >= 2 then
            StyleNewSlots(watched)
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local function HookEUIBank()
    if hooked then return true end
    local bank = GetBank()
    if not bank or type(bank.RefreshBank) ~= "function" then return false end

    hooksecurefunc(bank, "RefreshBank", function()
        ApplyCustomLayout(false)
        EnsureBatchHook(bank)
        StartBatchWatcher(bank)
    end)

    -- Reapply our text scale when EUI changes bag text sizes.
    if type(bank.RefreshTextSizes) == "function" then
        hooksecurefunc(bank, "RefreshTextSizes", function()
            if bank:IsShown() and ShouldApply(bank) then
                for _, btn in ipairs(bank._bankSlots or {}) do
                    textSignatureByButton[btn] = nil
                end
                StyleSlotRange(bank, 1, #(bank._bankSlots or {}), true)
            end
        end)
    end

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
        if not self:IsEnabled() then return end
        self._bg:SetColorTexture(0.13, 0.15, 0.16, 0.98)
        self._label:SetTextColor(1, 1, 1)
    end)
    b:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(0.08, 0.09, 0.10, 0.95)
        self._label:SetTextColor(0.90, 0.90, 0.90)
    end)
    b:SetScript("OnClick", onClick)

    function b:SetEBTEnabled(enabled)
        if enabled then self:Enable() else self:Disable() end
        self:SetAlpha(enabled and 1 or 0.45)
    end

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
    f:SetSize(470, 680)
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

    local version = MakeText(f, 10, "v" .. ADDON_VERSION, 0.45, 0.48, 0.50)
    version:SetPoint("LEFT", title, "RIGHT", 8, 0)

    local close = MakeButton(f, "x", 26, 24, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -10, -10)

    local subtitle = MakeText(f, 11,
        "Bank layout options for EllesmereUI.",
        0.62, 0.65, 0.68)
    subtitle:SetPoint("TOPLEFT", 24, -60)

    local selectedPresetKind
    local selectedPresetKey
    local selectedPresetIndex
    local presetMenu
    local presetButton
    local saveButton
    local updateButton
    local renameButton
    local deleteButton

    local function GetSelectedPreset()
        if selectedPresetKind == "builtin" then
            return BUILTIN_PRESETS[selectedPresetKey]
        elseif selectedPresetKind == "custom" then
            return DB.presets and DB.presets[selectedPresetIndex]
        end
    end

    local function SelectMatchingPreset()
        for _, name in ipairs(BUILTIN_ORDER) do
            if LayoutMatchesPreset(BUILTIN_PRESETS[name]) then
                selectedPresetKind = "builtin"
                selectedPresetKey = name
                selectedPresetIndex = nil
                return
            end
        end
        for i, preset in ipairs(DB.presets or {}) do
            if type(preset) == "table" and LayoutMatchesPreset(preset) then
                selectedPresetKind = "custom"
                selectedPresetKey = nil
                selectedPresetIndex = i
                return
            end
        end
        selectedPresetKind = nil
        selectedPresetKey = nil
        selectedPresetIndex = nil
    end

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
    local function Changed()
        if f.RefreshPresetControls then f:RefreshPresetControls() end
        ScheduleApply()
    end

    sliders[#sliders + 1] = MakeSlider(f, "Item slot size", -166, SLOT_MIN, SLOT_MAX, 1,
        function() return DB.slotSize end,
        function(v) DB.slotSize = v; Changed() end,
        function(v) return string.format("%d px", v) end)

    sliders[#sliders + 1] = MakeSlider(f, "Columns", -230, COL_MIN, COL_MAX, 1,
        function() return DB.columns end,
        function(v) DB.columns = v; Changed() end,
        function(v) return string.format("%d", v) end)

    sliders[#sliders + 1] = MakeSlider(f, "Horizontal spacing", -294, SPACE_MIN, SPACE_MAX, 1,
        function() return DB.spacingX end,
        function(v) DB.spacingX = v; Changed() end,
        function(v) return string.format("%d px", v) end)

    sliders[#sliders + 1] = MakeSlider(f, "Vertical spacing", -358, SPACE_MIN, SPACE_MAX, 1,
        function() return DB.spacingY end,
        function(v) DB.spacingY = v; Changed() end,
        function(v) return string.format("%d px", v) end)

    sliders[#sliders + 1] = MakeSlider(f, "Bank scale", -422, SCALE_MIN, SCALE_MAX, 0.01,
        function() return DB.bankScale end,
        function(v) DB.bankScale = v; Changed() end,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)

    sliders[#sliders + 1] = MakeSlider(f, "Item text scale", -486, TEXT_MIN, TEXT_MAX, 0.05,
        function() return DB.textScale end,
        function(v) DB.textScale = v; Changed() end,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)

    local presetDivider = f:CreateTexture(nil, "ARTWORK")
    presetDivider:SetPoint("TOPLEFT", 24, -548)
    presetDivider:SetPoint("TOPRIGHT", -24, -548)
    presetDivider:SetHeight(1)
    presetDivider:SetColorTexture(1, 1, 1, 0.08)

    local presetLabel = MakeText(f, 11, "Preset", 0.80, 0.82, 0.84)
    presetLabel:SetPoint("TOPLEFT", 24, -566)

    local presetWidth = 422
    local presetButtonWidth = 98
    local presetButtonGap = 10

    presetButton = MakeButton(f, "Custom", presetWidth, 28, function(self)
        if presetMenu:IsShown() then
            presetMenu:Hide()
        else
            f:BuildPresetMenu()
            presetMenu:Show()
        end
    end)
    presetButton:SetPoint("TOPLEFT", 24, -584)
    presetButton._label:ClearAllPoints()
    presetButton._label:SetPoint("LEFT", presetButton, "LEFT", 10, 0)
    presetButton._label:SetPoint("RIGHT", presetButton, "RIGHT", -28, 0)
    presetButton._label:SetJustifyH("LEFT")

    local arrow = MakeText(presetButton, 11, "v", 0.70, 0.72, 0.74)
    arrow:SetPoint("RIGHT", presetButton, "RIGHT", -10, 0)

    presetMenu = CreateFrame("Frame", nil, f)
    presetMenu:SetWidth(presetWidth)
    presetMenu:SetPoint("BOTTOMLEFT", presetButton, "TOPLEFT", 0, 4)
    presetMenu:SetFrameLevel(f:GetFrameLevel() + 30)
    presetMenu:EnableMouse(true)
    local menuBg = presetMenu:CreateTexture(nil, "BACKGROUND")
    menuBg:SetAllPoints()
    menuBg:SetColorTexture(0.035, 0.043, 0.050, 1)
    local menuBorder = presetMenu:CreateTexture(nil, "BORDER")
    menuBorder:SetPoint("TOPLEFT", -1, 1)
    menuBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    menuBorder:SetColorTexture(0.24, 0.26, 0.28, 1)
    presetMenu:Hide()

    local menuRows = {}
    local function AcquireMenuRow(index, isHeader)
        local row = menuRows[index]
        if not row then
            row = CreateFrame("Button", nil, presetMenu)
            row._bg = row:CreateTexture(nil, "BACKGROUND")
            row._bg:SetAllPoints()
            row._bg:SetColorTexture(1, 1, 1, 0)
            row._text = MakeText(row, 11, "", 0.88, 0.88, 0.88)
            row._text:SetPoint("LEFT", row, "LEFT", 10, 0)
            row._text:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            row._text:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(self)
                if self._isHeader then return end
                self._bg:SetColorTexture(1, 1, 1, 0.06)
            end)
            row:SetScript("OnLeave", function(self)
                self._bg:SetColorTexture(1, 1, 1, 0)
            end)
            menuRows[index] = row
        end
        row._isHeader = isHeader
        row:EnableMouse(not isHeader)
        row._text:SetTextColor(isHeader and 0.45 or 0.88, isHeader and 0.48 or 0.88, isHeader and 0.50 or 0.88)
        return row
    end

    function f:BuildPresetMenu()
        for _, row in ipairs(menuRows) do row:Hide() end
        local y = -4
        local rowIndex = 0

        local function Header(text)
            rowIndex = rowIndex + 1
            local row = AcquireMenuRow(rowIndex, true)
            row:SetSize(presetWidth, 20)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", presetMenu, "TOPLEFT", 0, y)
            row._text:SetText(text)
            row:SetScript("OnClick", nil)
            row:Show()
            y = y - 20
        end

        local function Item(text, onClick)
            rowIndex = rowIndex + 1
            local row = AcquireMenuRow(rowIndex, false)
            row:SetSize(presetWidth, 24)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", presetMenu, "TOPLEFT", 0, y)
            row._text:SetText(text)
            row:SetScript("OnClick", function()
                presetMenu:Hide()
                onClick()
            end)
            row:Show()
            y = y - 24
        end

        Header("Built-in")
        for _, name in ipairs(BUILTIN_ORDER) do
            local presetName = name
            Item(presetName, function()
                selectedPresetKind = "builtin"
                selectedPresetKey = presetName
                selectedPresetIndex = nil
                ApplyPresetValues(BUILTIN_PRESETS[presetName])
                f:RefreshControls()
                RefreshBankFromEUI()
            end)
        end

        if #(DB.presets or {}) > 0 then
            Header("My Presets")
            for i, preset in ipairs(DB.presets) do
                local index = i
                local name = Trim(preset.name)
                if name == "" then name = "Preset " .. index end
                Item(name, function()
                    selectedPresetKind = "custom"
                    selectedPresetKey = nil
                    selectedPresetIndex = index
                    ApplyPresetValues(DB.presets[index])
                    f:RefreshControls()
                    RefreshBankFromEUI()
                end)
            end
        end

        presetMenu:SetHeight(math.max(28, math.abs(y) + 4))
    end

    local dialogShade = CreateFrame("Frame", nil, f)
    dialogShade:SetAllPoints(f)
    dialogShade:SetFrameLevel(f:GetFrameLevel() + 50)
    dialogShade:EnableMouse(true)
    local shade = dialogShade:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.45)
    dialogShade:Hide()

    local dialog = CreateFrame("Frame", nil, dialogShade)
    dialog:SetSize(330, 160)
    dialog:SetPoint("CENTER")
    dialog:SetFrameLevel(dialogShade:GetFrameLevel() + 1)
    local dialogBg = dialog:CreateTexture(nil, "BACKGROUND")
    dialogBg:SetAllPoints()
    dialogBg:SetColorTexture(0.035, 0.043, 0.050, 1)
    local dialogBorder = dialog:CreateTexture(nil, "BORDER")
    dialogBorder:SetPoint("TOPLEFT", -1, 1)
    dialogBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    dialogBorder:SetColorTexture(0.24, 0.26, 0.28, 1)

    local dialogTitle = MakeText(dialog, 13, "Save preset", 1, 1, 1)
    dialogTitle:SetPoint("TOPLEFT", 16, -16)

    local dialogMessage = MakeText(dialog, 10, "", 0.65, 0.67, 0.69)
    dialogMessage:SetPoint("TOPLEFT", 16, -42)
    dialogMessage:SetPoint("TOPRIGHT", -16, -42)
    dialogMessage:SetJustifyH("LEFT")

    local presetEdit = CreateFrame("EditBox", nil, dialog)
    presetEdit:SetSize(298, 32)
    presetEdit:SetPoint("TOPLEFT", 16, -62)
    presetEdit:SetAutoFocus(false)
    presetEdit:SetMaxLetters(PRESET_NAME_MAX)
    presetEdit:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    presetEdit:SetTextColor(1, 1, 1)
    presetEdit:SetTextInsets(9, 9, 0, 0)

    local editBg = presetEdit:CreateTexture(nil, "BACKGROUND")
    editBg:SetAllPoints()
    editBg:SetColorTexture(0.07, 0.075, 0.08, 1)

    local editBorder = presetEdit:CreateTexture(nil, "BORDER")
    editBorder:SetPoint("TOPLEFT", -1, 1)
    editBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    editBorder:SetColorTexture(0.38, 0.40, 0.42, 1)

    local editPlaceholder = presetEdit:CreateFontString(nil, "OVERLAY")
    editPlaceholder:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    editPlaceholder:SetPoint("LEFT", presetEdit, "LEFT", 9, 0)
    editPlaceholder:SetText("Type a preset name...")
    editPlaceholder:SetTextColor(0.50, 0.52, 0.54)

    local function RefreshEditPlaceholder()
        editPlaceholder:SetShown(not presetEdit:HasFocus() and presetEdit:GetText() == "")
    end

    presetEdit:SetScript("OnEditFocusGained", function()
        editBorder:SetColorTexture(0.047, 0.824, 0.616, 1)
        RefreshEditPlaceholder()
    end)
    presetEdit:SetScript("OnEditFocusLost", function()
        editBorder:SetColorTexture(0.38, 0.40, 0.42, 1)
        RefreshEditPlaceholder()
    end)
    presetEdit:SetScript("OnTextChanged", RefreshEditPlaceholder)
    RefreshEditPlaceholder()

    local dialogError = MakeText(dialog, 10, "", 0.95, 0.35, 0.35)
    dialogError:SetPoint("TOPLEFT", 16, -96)

    local dialogMode
    local dialogIndex
    local acceptButton

    local cancelButton = MakeButton(dialog, "Cancel", 92, 26, function()
        dialogShade:Hide()
    end)
    cancelButton:SetPoint("BOTTOMRIGHT", -16, 14)

    local function ValidatePresetName(name, skipIndex)
        name = Trim(name)
        if name == "" then return nil, "Enter a preset name." end
        if IsBuiltinPresetName(name) then return nil, "That name is reserved for a built-in preset." end
        if FindCustomPresetByName(name, skipIndex) then return nil, "A preset with that name already exists." end
        return name
    end

    local function FinishDialog()
        if dialogMode == "delete" then
            if DB.presets and DB.presets[dialogIndex] then
                table.remove(DB.presets, dialogIndex)
            end
            selectedPresetKind = nil
            selectedPresetKey = nil
            selectedPresetIndex = nil
            SelectMatchingPreset()
            dialogShade:Hide()
            f:RefreshPresetControls()
            return
        end

        local name, err = ValidatePresetName(presetEdit:GetText(), dialogMode == "rename" and dialogIndex or nil)
        if not name then
            dialogError:SetText(err or "Invalid preset name.")
            return
        end

        if dialogMode == "save" then
            if #(DB.presets or {}) >= MAX_CUSTOM_PRESETS then
                dialogError:SetText("You can save up to " .. MAX_CUSTOM_PRESETS .. " presets.")
                return
            end
            local data = CaptureLayoutSettings()
            data.name = name
            DB.presets[#DB.presets + 1] = data
            selectedPresetKind = "custom"
            selectedPresetKey = nil
            selectedPresetIndex = #DB.presets
        elseif dialogMode == "rename" then
            local preset = DB.presets and DB.presets[dialogIndex]
            if not preset then return end
            preset.name = name
            selectedPresetKind = "custom"
            selectedPresetKey = nil
            selectedPresetIndex = dialogIndex
        end

        dialogShade:Hide()
        f:RefreshPresetControls()
    end

    acceptButton = MakeButton(dialog, "Save", 92, 26, FinishDialog)
    acceptButton:SetPoint("RIGHT", cancelButton, "LEFT", -8, 0)

    presetEdit:SetScript("OnEnterPressed", FinishDialog)
    presetEdit:SetScript("OnEscapePressed", function() dialogShade:Hide() end)

    local function ShowPresetDialog(mode, index)
        dialogMode = mode
        dialogIndex = index
        dialogError:SetText("")
        dialogMessage:SetText("")
        presetEdit:Show()

        if mode == "save" then
            dialogTitle:SetText("Save preset")
            dialogMessage:SetText("Preset name")
            acceptButton._label:SetText("Save")
            presetEdit:SetText("")
            presetEdit:SetFocus()
        elseif mode == "rename" then
            local preset = DB.presets and DB.presets[index]
            if not preset then return end
            dialogTitle:SetText("Rename preset")
            dialogMessage:SetText("Preset name")
            acceptButton._label:SetText("Rename")
            presetEdit:SetText(preset.name or "")
            presetEdit:SetFocus()
            presetEdit:HighlightText()
        elseif mode == "delete" then
            local preset = DB.presets and DB.presets[index]
            if not preset then return end
            dialogTitle:SetText("Delete preset?")
            dialogMessage:SetText("Delete \"" .. (preset.name or "Preset") .. "\"?")
            acceptButton._label:SetText("Delete")
            presetEdit:Hide()
        end

        dialogShade:Show()
    end

    saveButton = MakeButton(f, "Save New", presetButtonWidth, 26, function()
        ShowPresetDialog("save")
    end)
    saveButton:SetPoint("TOPLEFT", 24, -620)

    updateButton = MakeButton(f, "Update", presetButtonWidth, 26, function()
        if selectedPresetKind ~= "custom" then return end
        local preset = DB.presets and DB.presets[selectedPresetIndex]
        if not preset then return end
        local name = preset.name
        local data = CaptureLayoutSettings()
        data.name = name
        DB.presets[selectedPresetIndex] = data
        f:RefreshPresetControls()
    end)
    updateButton:SetPoint("LEFT", saveButton, "RIGHT", presetButtonGap, 0)

    renameButton = MakeButton(f, "Rename", presetButtonWidth, 26, function()
        if selectedPresetKind == "custom" then
            ShowPresetDialog("rename", selectedPresetIndex)
        end
    end)
    renameButton:SetPoint("LEFT", updateButton, "RIGHT", presetButtonGap, 0)

    deleteButton = MakeButton(f, "Delete", presetButtonWidth, 26, function()
        if selectedPresetKind == "custom" then
            ShowPresetDialog("delete", selectedPresetIndex)
        end
    end)
    deleteButton:SetPoint("LEFT", renameButton, "RIGHT", presetButtonGap, 0)

    local hint = MakeText(f, 10, "Built-in presets are read-only. Custom presets save layout values only.", 0.48, 0.52, 0.54)
    hint:SetWidth(presetWidth)
    hint:SetJustifyH("CENTER")
    hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)

    function f:RefreshPresetControls()
        local preset = GetSelectedPreset()
        local dirty = preset and not LayoutMatchesPreset(preset)
        local label

        if selectedPresetKind == "builtin" and selectedPresetKey then
            label = selectedPresetKey .. (dirty and " *" or "")
        elseif selectedPresetKind == "custom" and preset then
            label = (preset.name or "Preset") .. (dirty and " *" or "")
        else
            label = "Custom"
        end

        presetButton._label:SetText(label)
        local isCustom = selectedPresetKind == "custom" and preset ~= nil
        updateButton:SetEBTEnabled(isCustom)
        renameButton:SetEBTEnabled(isCustom)
        deleteButton:SetEBTEnabled(isCustom)
        saveButton:SetEBTEnabled(#(DB.presets or {}) < MAX_CUSTOM_PRESETS)
    end

    function f:RefreshControls()
        enableRow:Refresh()
        warbandRow:Refresh()
        for _, slider in ipairs(sliders) do slider:Refresh() end
        self:RefreshPresetControls()
    end

    f:SetScript("OnShow", function(self)
        SelectMatchingPreset()
        self:RefreshControls()
        if not HookEUIBank() then
            C_Timer.After(0.5, HookEUIBank)
        end
    end)

    f:SetScript("OnHide", function()
        presetMenu:Hide()
        dialogShade:Hide()
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
