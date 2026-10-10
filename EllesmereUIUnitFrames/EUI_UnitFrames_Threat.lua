if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Threat.lua
--
--  Threat display on the unit frames: the additive Player Threat border
--  and the threat % text on target and focus (WoW Forever only). Loads
--  after the main file and reads it through ns and ns._internals;
--  db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local issecretvalue = issecretvalue
local PP = EllesmereUI.PP

local I = ns._internals
local frames, GetSelectedFont, SetFSFont = I.frames, I.GetSelectedFont, I.SetFSFont
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  Player Threat border (additive "Shadow" style on the PLAYER frame)
--
--  Zero cost unless enabled: no frame created, no event registered until the
--  option is on. When on, watches ONLY the player's own threat (RegisterUnitEvent
--  ... "player") plus minimal combat/zone boundaries to clear it; shows only in
--  instanced content (party/raid/delve) while grouped -- mirrors nameplate non-tank logic.
-------------------------------------------------------------------------------
local _ptWatcher       -- lazily-created event frame
local _ptOn = false    -- the watcher's events are registered
local _ptShownState    -- nil / "has" / "near" -- skip redundant re-apply

-- party/raid/delve instances only (mirrors the nameplate threat-context gate)
local function PT_InInstancedContent()
    local _, instanceType, difficultyID = GetInstanceInfo()
    if (tonumber(difficultyID) or 0) == 0 then return false end
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then return false end
    local isDelve = C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()
    return instanceType == "party" or instanceType == "raid" or isDelve
end

-- Lazily create the dedicated additive shadow border on the player frame. It
-- sits behind the frame like the real "Shadow" border style, separate from the
-- unified border so it ADDS to whatever border the user already has.
local function PT_EnsureBorder(pf)
    if pf._threatShadowBorder then return pf._threatShadowBorder end
    local b = CreateFrame("Frame", nil, pf)
    PP.Point(b, "TOPLEFT", pf, "TOPLEFT", 0, 0)
    PP.Point(b, "BOTTOMRIGHT", pf, "BOTTOMRIGHT", 0, 0)
    b:SetFrameLevel(math.max(0, pf:GetFrameLevel() - 1))
    b:Hide()
    pf._threatShadowBorder = b
    return b
end

local function PT_Hide()
    local pf = frames.player
    if pf and pf._threatShadowBorder then pf._threatShadowBorder:Hide() end
    _ptShownState = nil
end

-- Render the additive Shadow border (size 2) tinted with the threat color --
-- identical to picking "Shadow" at size 2 from the Border Style dropdown.
local function PT_Show(state, c)
    local pf = frames.player
    if not pf then return end
    local b = PT_EnsureBorder(pf)
    if _ptShownState ~= state then
        _ptShownState = state
        EllesmereUI.ApplyBorderStyle(b, 2, c.r, c.g, c.b, 1, "shadow", nil, nil, nil, nil, "unitframes", 2)
    else
        EllesmereUI.SetBorderStyleColor(b, c.r, c.g, c.b, 1)
    end
    b:Show()
end

-- Re-evaluate the player's threat and paint/clear the additive shadow border.
function ns.UpdatePlayerThreatBorder()
    if not (db and db.profile and db.profile.playerThreatBorderEnabled) then PT_Hide(); return end
    if not frames.player then return end
    if not PT_InInstancedContent() or not IsInGroup() then PT_Hide(); return end
    local status = UnitThreatSituation("player")
    if status and status >= 2 then
        -- status 2/3: the mob is on you -- you have aggro.
        PT_Show("has", db.profile.playerThreatHasAggroColor or { r = 1, g = 0.5, b = 0 })
    elseif status == 1 then
        -- status 1: higher threat than the tank but not tanking yet -- close to aggro.
        PT_Show("near", db.profile.playerThreatNearAggroColor or { r = 0.81, g = 0.72, b = 0.19 })
    else
        PT_Hide()
    end
end

-- Enable/disable the watcher. Registers ONLY the player's own threat event plus
-- the minimal boundaries to clear it; tears everything down and hides when off.
function ns.SetPlayerThreatEnabled(on)
    _ptOn = on and true or false
    if on then
        if not _ptWatcher then
            _ptWatcher = CreateFrame("Frame")
            _ptWatcher:SetScript("OnEvent", function() ns.UpdatePlayerThreatBorder() end)
        end
        _ptWatcher:RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", "player")
        _ptWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        _ptWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
        _ptWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        _ptWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
        ns.UpdatePlayerThreatBorder()
    else
        if _ptWatcher then _ptWatcher:UnregisterAllEvents() end
        PT_Hide()
    end
end

-- Login and every real reload pass (profile switch, spec override, import):
-- the saved toggle never reaches SetPlayerThreatEnabled any other way.
function ns.SyncPlayerThreat()
    local want = db.profile.playerThreatBorderEnabled == true
    if want ~= _ptOn then
        ns.SetPlayerThreatEnabled(want)
    elseif want then
        ns.UpdatePlayerThreatBorder()
    end
end

-------------------------------------------------------------------------------
--  Threat % text on the target and focus frames (WoW Forever only; retail
--  defines none of it). The watcher carries no events until
--  SetThreatPctEnabled(true).
-------------------------------------------------------------------------------
if EllesmereUI.IS_FOREVER then
    -- Inside spots sit on the health bar; outside spots sit beside the whole
    -- frame (past an attached portrait), centred on its height.
    local POS = {
        RIGHT  = { point = "RIGHT",  x = -4 },
        LEFT   = { point = "LEFT",   x = 4 },
        CENTER = { point = "CENTER", x = 0 },
        OUTRIGHT = { point = "LEFT",  rel = "RIGHT", x = 4,  outside = true },
        OUTLEFT  = { point = "RIGHT", rel = "LEFT",  x = -4, outside = true },
    }
    local watcher = CreateFrame("Frame")

    local function Layout(frame, fs)
        local p = db.profile
        local posKey = POS[p.threatPctPosition] and p.threatPctPosition or "CENTER"
        local size = p.threatPctSize
        local x, y = p.threatPctXOffset, p.threatPctYOffset
        local font = GetSelectedFont()
        local outline = EllesmereUI.GetFontOutlineFlag("unitFrames")
        if frame._tpPos == posKey and frame._tpSize == size and frame._tpX == x and frame._tpY == y
            and frame._tpFont == font and frame._tpOutline == outline then
            return
        end
        frame._tpPos, frame._tpSize, frame._tpX, frame._tpY = posKey, size, x, y
        frame._tpFont, frame._tpOutline = font, outline
        local pos = POS[posKey]
        SetFSFont(fs, size)
        fs:ClearAllPoints()
        PP.Point(fs, pos.point, pos.outside and frame or frame.Health, pos.rel or pos.point, pos.x + x, y)
        fs:SetJustifyH(pos.point)
    end

    -- The percent may be secret: only type() and issecretvalue() read it here
    -- (a readable 0 hides the text), then it goes straight to PaintThreatPct.
    local function UpdateUnit(unit)
        local frame = frames[unit]
        if not (frame and frame._textOverlay) then return end
        local fs = frame._threatPctText
        local p = db.profile
        if p.threatPctEnabled and (unit == "target" or p.threatPctFocus) then
            local isTanking, status, pct = UnitDetailedThreatSituation("player", unit)
            if type(pct) == "number" and (issecretvalue(pct) or pct ~= 0) then
                if not fs then
                    fs = frame._textOverlay:CreateFontString(nil, "OVERLAY")
                    fs:SetWordWrap(false)
                    frame._threatPctText = fs
                end
                Layout(frame, fs)
                EllesmereUI.PaintThreatPct(fs, pct, status, isTanking, p.threatPctColorByThreat)
                fs:Show()
                return
            end
        end
        if fs then fs:Hide() end
    end

    local function UpdateAll()
        UpdateUnit("target")
        UpdateUnit("focus")
    end

    local function OnEvent(_, event, unit)
        if event == "UNIT_THREAT_LIST_UPDATE" then
            UpdateUnit(unit)
        elseif event == "PLAYER_TARGET_CHANGED" then
            UpdateUnit("target")
        elseif event == "PLAYER_FOCUS_CHANGED" then
            UpdateUnit("focus")
        else
            UpdateAll()
        end
    end

    watcher:SetScript("OnEvent", OnEvent)

    -- Events only while on AND an EllesmereUI target or focus frame exists
    -- (a frame source change reloads, so the frames never appear later).
    local tpOn = false
    function ns.SetThreatPctEnabled(on)
        on = on == true and (frames.target or frames.focus) ~= nil
        if on ~= tpOn then
            tpOn = on
            if on then
                watcher:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", "target", "focus")
                watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
                watcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
                watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                watcher:UnregisterAllEvents()
            end
        end
        UpdateAll()
    end

    -- Login and every real reload pass (profile switch, spec override, import):
    -- the saved toggle never reaches SetThreatPctEnabled any other way.
    function ns.SyncThreatPct()
        local want = db.profile.threatPctEnabled == true and (frames.target or frames.focus) ~= nil
        if want ~= tpOn then
            ns.SetThreatPctEnabled(want)
        elseif want then
            UpdateAll()
        end
    end

    -- Options setters of the position, size, offset and colour keys (the
    -- layout memo compares every layout input).
    ns.RefreshThreatPct = UpdateAll
end -- IS_FOREVER
