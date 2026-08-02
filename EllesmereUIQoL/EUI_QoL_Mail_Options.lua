-------------------------------------------------------------------------------
--  EUI_QoL_Mail_Options.lua
--  Options section for the mailbox improvements. Embedded in the Quality of
--  Life page below the Bloodlust Tracker section.
--
--  The individual parts live in a cog popup on the master toggle rather than in
--  rows of their own, so the section stays one row tall however many parts it
--  gains.
-------------------------------------------------------------------------------

-- Must match SUB_DEFAULTS in EllesmereUIQoL_Mail.lua.
local SUB_DEFAULTS = {
    ctrlReturn     = true,
    itemTooltip    = true,
    subjectTooltip = true,
}

local function Cfg()
    if not EllesmereUIDB then return {} end
    EllesmereUIDB.mailImprovements = EllesmereUIDB.mailImprovements or {}
    return EllesmereUIDB.mailImprovements
end

local function Get(key)
    local v = Cfg()[key]
    if v == nil then return SUB_DEFAULTS[key] end
    return v and true or false
end

local function Set(key, v)
    Cfg()[key] = v and true or false
end

-- Section-only builder for embedding in the Quality of Life page. Returns the
-- total height consumed.
_G._EUI_BuildMailSection = function(parent, yOffset, W, PP)
    local y = yOffset
    local _, h, row

    _, h = W:SectionHeader(parent, "MAILBOX IMPROVEMENTS", y); y = y - h

    row, h = W:DualRow(parent, y,
        { type    = "toggle",
          text    = "Enable Mailbox Improvements",
          tooltip = "Adds a ctrl-click return shortcut and richer hover text to the inbox. The default click behaviour is untouched.",
          getValue = function() return Cfg().enabled == true end,
          setValue = function(v)
              Cfg().enabled = v or nil
              -- Installs the row hooks on the spot when switched on at the
              -- mailbox, and drops the mailbox events again when switched off.
              if _G._EUI_Mail_Check then _G._EUI_Mail_Check() end
              EllesmereUI:RefreshPage()
          end },
        { type = "label", text = "" }
    ); y = y - h

    -- Cog on the master toggle (left region).
    do
        local rgn = row._leftRegion
        local function MailOff() return Cfg().enabled ~= true end

        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Mailbox Improvements Settings",
            captureRegion = rgn,
            rows = {
                { type = "toggle", label = "Ctrl-Click Returns to Sender",
                  get = function() return Get("ctrlReturn") end,
                  set = function(v) Set("ctrlReturn", v) end },
                { type = "toggle", label = "List Attachments on Hover",
                  get = function() return Get("itemTooltip") end,
                  set = function(v) Set("itemTooltip", v) end },
                { type = "toggle", label = "Show Full Subject on Hover",
                  get = function() return Get("subjectTooltip") end,
                  set = function(v) Set("subjectTooltip", v) end },
            },
        })

        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(MailOff() and 0.15 or 0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints()
        cogTex:SetTexture(EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(MailOff() and 0.15 or 0.4) end)
        cogBtn:SetScript("OnClick", function(self) cogShow(self) end)

        -- Blocks and explains the cog while the feature is off.
        local cogBlock = CreateFrame("Frame", nil, cogBtn)
        cogBlock:SetAllPoints()
        cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10)
        cogBlock:EnableMouse(true)
        cogBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Mailbox Improvements"))
        end)
        cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        EllesmereUI.RegisterWidgetRefresh(function()
            local off = MailOff()
            cogBtn:SetAlpha(off and 0.15 or 0.4)
            if off then cogBlock:Show() else cogBlock:Hide() end
        end)
        if MailOff() then cogBlock:Show() else cogBlock:Hide() end
    end

    _, h = W:Spacer(parent, y, 20); y = y - h

    return math.abs(y - yOffset)
end
