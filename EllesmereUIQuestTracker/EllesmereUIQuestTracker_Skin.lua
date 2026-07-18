-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_Skin.lua
--
-- Restyles Blizzard's ObjectiveTrackerFrame sub-trackers (headers, blocks,
-- progress bars, timer bars) via hooks only. Never SetScript on any tracker
-- frame; HookScript only. No frame-tree recursion.
--
-- Styling targets (match the legacy custom tracker exactly):
--   title color      = { r=1.00, g=0.91, b=0.47 }  gold
--   objective color  = { r=0.72, g=0.72, b=0.72 }  gray
--   completed color  = { r=0.25, g=1.00, b=0.35 }  green
--   section accent   = live EllesmereUI.ELLESMERE_GREEN
--   bar bg           = { r=0.15, g=0.15, b=0.15 } at 0.8 alpha
--   bar fill         = accent tint on Blizzard's default statusbar texture
--   timer fill       = { r=1.00, g=0.82, b=0.20 }
--   timer low fill   = { r=1.00, g=0.30, b=0.30 }
--   font             = EllesmereUI.GetFontPath("unitFrames")
--   shadow / outline = EllesmereUI.GetFontUseShadow / GetFontOutlineFlag
--   border           = PanelPP.CreateBorder 1px black, physical pixel perfect
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT

-- External weak-keyed table for block skin state (never write custom keys
-- onto Blizzard pool frames -- causes taint).
local _skinned = setmetatable({}, { __mode = "k" })


-- Color helpers. All four user-facing text colors come from DB so they
-- follow the Colors section in the options page.
local function GetTitleRGB()
    local c = EQT.DB()
    return c.titleR or 1.0, c.titleG or 0.910, c.titleB or 0.471
end
local function GetCompletedRGB()
    local c = EQT.DB()
    return c.completedR or 0.251, c.completedG or 1.0, c.completedB or 0.349
end
local function GetFocusRGB()
    local c = EQT.DB()
    return c.focusR or 0.871, c.focusG or 0.251, c.focusB or 1.0
end
local SUB_TRACKERS = {
    "ScenarioObjectiveTracker",
    "UIWidgetObjectiveTracker",
    "CampaignQuestObjectiveTracker",
    "QuestObjectiveTracker",
    "AdventureObjectiveTracker",
    "AchievementObjectiveTracker",
    "MonthlyActivitiesObjectiveTracker",
    "ProfessionsRecipeTracker",
    "BonusObjectiveTracker",
    "WorldQuestObjectiveTracker",
    "InitiativeTasksObjectiveTracker",
}

-- ScenarioObjectiveTracker and UIWidgetObjectiveTracker render their content
-- through Blizzard's shared UI-widget pool -- the same pool GameTooltip and
-- AreaPOI tooltips draw from. ANY method call on their child blocks taints
-- that pool, and the taint surfaces later as "attempt to compare a secret
-- number value" in LayoutFrame.lua when a tooltip lays out a widget set
-- (e.g. hovering an AreaPOI on the world map). We only ever skin their
-- headers; block-level loops must skip them entirely.
local function SharesWidgetPool(tracker)
    return tracker == _G.ScenarioObjectiveTracker
        or tracker == _G.UIWidgetObjectiveTracker
end

-- Shared font sizes -- read from DB so the options panel can tweak them.
-- Defaults are seeded in the loader's QT_DEFAULTS table.
local function GetTitleSize() return EQT.Cfg("titleFontSize")     or 13 end
local function GetObjSize()   return EQT.Cfg("objectiveFontSize") or 11 end

-------------------------------------------------------------------------------
-- External weak-keyed flag tables. Never write custom fields onto Blizzard-
-- owned tables: the tracker iterates its own data tables (e.g. tracker.blocks
-- keyed by blockID) with pairs(), and any stray key becomes a "fake entry"
-- that breaks their MarkBlocksUnused logic. All idempotency flags live here.
-------------------------------------------------------------------------------
local _hookedTrackers    = setmetatable({}, { __mode = "k" })
local _hookedBlocks      = setmetatable({}, { __mode = "k" })
local _blockIcons        = setmetatable({}, { __mode = "k" })  -- block -> our icon texture

-- External weak-keyed flag tables. Every "am I in a state?" bool / number
-- we used to write directly onto Blizzard-owned frames (block, tracker,
-- line, FontString, StatusBar, bar, etc.) lives here instead so Blizzard's
-- iteration of its own tables never sees our additions. This is the
-- canonical taint-avoidance pattern per CLAUDE.md.
local _blockFocus        = setmetatable({}, { __mode = "k" })  -- block -> focus texture
local _headerClickOverlays = setmetatable({}, { __mode = "k" })  -- header -> click overlay

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function GetAccent()
    local eg = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    if eg then return eg.r, eg.g, eg.b end
    return 0.047, 0.824, 0.624
end

local function GetFont()
    local db = _G._EQT_DB
    local fontKey = db and db.profile and db.profile.questTracker and db.profile.questTracker.font
    if fontKey and fontKey ~= "__global" then
        if EllesmereUI and EllesmereUI.ResolveFontName then
            return EllesmereUI.ResolveFontName(fontKey) or "Fonts/FRIZQT__.TTF"
        end
    end
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("questTracker") or "Fonts/FRIZQT__.TTF"
    end
    return "Fonts/FRIZQT__.TTF"
end

local function GetOutline()
    if EllesmereUI and EllesmereUI.GetFontOutlineFlag then
        return EllesmereUI.GetFontOutlineFlag("questTracker") or ""
    end
    return ""
end

local function ApplyShadow(fs)
    if not fs then return end
    local useShadow = (EllesmereUI and EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow("questTracker")) and true or false
    -- 12.0.7: instance shadows no longer render; shadow must ride a FontObject.
    -- These are Blizzard objective-tracker strings, so capture and restore the
    -- current font face around PrimeFontShadow to preserve Blizzard's typeface.
    local _pf, _ps, _pfl = fs:GetFont()
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, useShadow) end
    if _pf then fs:SetFont(_pf, _ps, _pfl) end
end

-- Registry of every FontString we've styled. Lets us re-template in bulk
-- when the user changes font path / outline / shadow settings.
local _eqtFontRegistry = setmetatable({}, { __mode = "k" })

-- Reapplies EUI font path with explicit size + outline + shadow.
-- If `size` is nil, preserves Blizzard's current size.
local function StyleFontStringSized(fs, size)
    if not fs or not fs.GetFont then return end
    if not size then
        local _, cur = fs:GetFont()
        size = cur or 12
    end
    local ok = pcall(fs.SetFont, fs, GetFont(), size, GetOutline())
    if not ok then fs:SetFont("Fonts/FRIZQT__.TTF", size, GetOutline()) end
    ApplyShadow(fs)
    _eqtFontRegistry[fs] = true
end

-- Convenience wrappers so every title / objective uses the shared sizes.
local function StyleFontString(fs)     StyleFontStringSized(fs, nil)            end
local function StyleTitleFS(fs)        StyleFontStringSized(fs, GetTitleSize()) end
local function StyleObjectiveFS(fs)    StyleFontStringSized(fs, GetObjSize())   end

-- Walk every FontString region on a frame (top-level only) and restyle it.
-- No recursion: child frames each go through their own skin call.
local function StyleAllFontStrings(frame)
    if not frame or not frame.GetRegions then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region and region:GetObjectType() == "FontString" then
            StyleFontString(region)
        end
    end
end

-- Bulk re-template everything we've touched. Called when user changes font
-- settings in options.
function EQT.RefreshFonts()
    for fs in pairs(_eqtFontRegistry) do
        if fs and fs.GetFont then
            local _, size = fs:GetFont()
            pcall(fs.SetFont, fs, GetFont(), size or 12, GetOutline())
            ApplyShadow(fs)
        end
    end
end

-- Forces Blizzard to fully recompute block heights/positions after we
-- resize existing FontStrings (RestyleAll) or Blizzard only partially
-- relayouts around a focus change -- both leave stale cached block heights
-- that overlap the next block until a full ObjectiveTrackerFrame:Update()
-- runs (normally only happens on /reload).
--
-- Deferred via C_Timer.After(0) so this never runs inline inside whatever
-- callback triggered it: the documented SplashFrame taint (see
-- EllesmereUIQuestTracker_QoL.lua) came from calling Update() SYNCHRONOUSLY
-- inside a Blizzard secure call chain (OnHide during a quest turn-in flow).
-- A fresh timer tick, fired from a plain insecure options-panel action or
-- event handler, has no such ancestor. Also combat-gated because Update()
-- rebuilds the tracker's secure quest-item action buttons; if combat is
-- active when the tick fires, retry once on PLAYER_REGEN_ENABLED instead of
-- silently dropping the request.
--
-- TAINT-LOG VERIFIED 2026-07-10 (taintLog 1, empty log): the exact deferred +
-- combat-gated shape here -- relayout trigger, immediately enter combat, use
-- a quest-item button -- leaves no blocking taint on the current client. That
-- verification covers ONLY this shape: the retry listener is one-shot (it
-- unregisters on fire and re-arms per deferral) so Update() never runs more
-- often than requested, and the SYNCHRONOUS case in the QoL SplashFrame fix
-- remains forbidden. Do not widen this pattern without re-verifying.
local _relayoutPending = false
local _relayoutRetryFrame = nil
local function DoTrackerRelayout()
    if InCombatLockdown() then
        if not _relayoutRetryFrame then
            _relayoutRetryFrame = CreateFrame("Frame")
            if not EQT._eventFrames then EQT._eventFrames = {} end
            if not EQT._eventRegistrations then EQT._eventRegistrations = {} end
            local idx = #EQT._eventFrames + 1
            EQT._eventFrames[idx] = _relayoutRetryFrame
            EQT._eventRegistrations[idx] = {"PLAYER_REGEN_ENABLED"}
            _relayoutRetryFrame:SetScript("OnEvent", function(self)
                -- One-shot: without this, every combat end for the rest of the
                -- session would run a full tracker Update nobody asked for.
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if EQT.ForceTrackerRelayout then EQT.ForceTrackerRelayout() end
            end)
        end
        _relayoutRetryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local otf = _G.ObjectiveTrackerFrame
    if otf and otf.Update then
        -- 12.1: Blizzard's scenario layout probes player auras during Update
        -- (ShouldShowMawBuffs -> GetAuraDataByIndex), and aura APIs hard-error
        -- when auras are secret and the caller is tainted -- which our forced
        -- Update() is. Probe the same access first and skip the relayout while
        -- secret; the tracker relayouts naturally on Blizzard's next update.
        if EllesmereUI and EllesmereUI.IS_121
           and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok = pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")
            if not ok then return end
        end
        otf:Update()
    end
end
function EQT.ForceTrackerRelayout()
    if _relayoutPending then return end
    _relayoutPending = true
    C_Timer.After(0, function()
        _relayoutPending = false
        DoTrackerRelayout()
    end)
end

-- Physical-pixel-perfect 1px accent divider under each section header.
-- Parented to ObjectiveTrackerFrame (NOT the header) so collapse/expand
-- animations on the header don't drag our divider with them. Keyed by
-- header so we only create one per section (Quests, Professions, etc).
-- Follows the canonical border pattern: DisablePixelSnap + SetHeight via
-- PP.perfect / effectiveScale.
local _headerDividers = setmetatable({}, { __mode = "k" })
local function EnsureAccentDivider(header)
    if not header or not header.CreateTexture then return nil end
    local otf = _G.ObjectiveTrackerFrame
    if not otf or not otf.CreateTexture then return nil end

    -- Never draw a divider for the master "All Objectives" header or its
    -- menu bar -- those are hidden sections at the top of the tracker.
    if header == otf.HeaderMenu or header == otf.Header then return nil end

    -- Divider is visible only when the tracker itself is currently being
    -- rendered (Blizzard hides the tracker frame when it has no content).
    -- Signals, ORed:
    --   tracker has any block, OR
    --   tracker is flagged as having contents (hasContents), OR
    --   tracker was displayed on the last layout pass (wasDisplayedLastLayout).
    -- Any of those == the section is still active. All false == fully hidden.
    -- Collapse keeps hasContents/wasDisplayedLastLayout true, so collapsed
    -- trackers still show their divider.
    local owner = header:GetParent()
    local hasAnyBlock = false
    if owner and owner.usedBlocks then
        for _, byTemplate in pairs(owner.usedBlocks) do
            if type(byTemplate) == "table" then
                for _ in pairs(byTemplate) do
                    hasAnyBlock = true
                    break
                end
                if hasAnyBlock then break end
            end
        end
    end
    -- The divider belongs to a section that is actually rendered. Require
    -- the header itself to be shown right now AND the tracker to have some
    -- current content signal. `wasDisplayedLastLayout` alone isn't enough
    -- because Blizzard doesn't always clear it when a section empties.
    local headerShown = header.IsShown and header:IsShown()
    local trackerShown = owner and owner.IsShown and owner:IsShown()
    local hasContentSignal = hasAnyBlock or (owner and owner.hasContents)
    local active = headerShown and trackerShown and hasContentSignal
    if not active then
        local tex = _headerDividers[header]
        if tex then tex:Hide() end
        return nil
    end
    local tex = _headerDividers[header]
    if not tex then
        tex = otf:CreateTexture(nil, "OVERLAY")
        _headerDividers[header] = tex
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT",  header, "BOTTOMLEFT",  7, 0)
    tex:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -1, 0)
    local PP_CORE = EllesmereUI and EllesmereUI.PP
    local PP_SEC  = EllesmereUI and EllesmereUI.PanelPP
    if PP_SEC and PP_SEC.DisablePixelSnap then PP_SEC.DisablePixelSnap(tex) end
    local perfect = (PP_CORE and PP_CORE.perfect) or (PP_SEC and PP_SEC.mult) or 1
    local es = header.GetEffectiveScale and header:GetEffectiveScale() or 1
    local onePixel = (es and es > 0) and (perfect / es) or (PP_SEC and PP_SEC.mult) or 1
    tex:SetHeight(onePixel)
    local r, g, b = GetAccent()
    tex:SetColorTexture(r, g, b, 1)
    tex:Show()
    return tex
end

-------------------------------------------------------------------------------
-- Strip every Texture region on a frame except ones explicitly preserved.
-- Top-level only, never recurses. Leaves FontStrings alone.
-------------------------------------------------------------------------------
local function StripTextures(frame, keep)
    if not frame or not frame.GetRegions then return end
    keep = keep or {}
    -- IMPORTANT: hide via SetTexture("") only. SetTexture(nil) and
    -- SetAlpha(0) both taint Blizzard-owned textures. Tainted widget-pool
    -- textures cause arithmetic errors when the pool reuses them for
    -- tooltip/POI widgets later (Blizzard_UIWidgetTemplateTextWithState
    -- textHeight crashes).
    for _, region in ipairs({ frame:GetRegions() }) do
        if region and region:GetObjectType() == "Texture" and not keep[region]
           and region.SetTexture then
            region:SetTexture("")
        end
    end
end

-------------------------------------------------------------------------------
-- Header skin: accent color + EUI font. Strips every decorative texture
-- region from the header; keeps the minimize button (+/-) and Text intact.
-------------------------------------------------------------------------------
local function SkinHeader(header)
    if not header then return end
    if not EQT.Cfg("skinHeaders") then return end

    -- Named decorative regions we always want gone.
    -- Hide via SetTexture("") only (anti-taint pattern -- see StripTextures).
    for _, k in ipairs({
        "Background", "Line", "LineSheen", "LineGlow", "Divider",
        "Sheen", "Glow", "Stripe",
    }) do
        local r = header[k]
        if r and r.SetTexture then r:SetTexture("") end
    end

    -- Sweep anonymous Texture regions too. Preserve the minimize button's
    -- textures by skipping anything owned by header.MinimizeButton.
    local minBtn = header.MinimizeButton
    local keep = {}
    if minBtn and minBtn.GetRegions then
        for _, region in ipairs({ minBtn:GetRegions() }) do
            keep[region] = true
        end
        if minBtn.GetNormalTexture and minBtn:GetNormalTexture() then
            keep[minBtn:GetNormalTexture()] = true
        end
        if minBtn.GetPushedTexture and minBtn:GetPushedTexture() then
            keep[minBtn:GetPushedTexture()] = true
        end
        if minBtn.GetHighlightTexture and minBtn:GetHighlightTexture() then
            keep[minBtn:GetHighlightTexture()] = true
        end
    end
    StripTextures(header, keep)

    -- Accent-tint the +/- minimize button. Desaturate first so the base
    -- atlas's built-in tint doesn't multiply with our accent.
    if minBtn and EQT.Cfg("accentHeaders") then
        local r, g, b = GetAccent()
        local function tint(tex)
            if not tex then return end
            if tex.SetDesaturated then tex:SetDesaturated(true) end
            if tex.SetVertexColor then tex:SetVertexColor(r, g, b) end
        end
        tint(minBtn.GetNormalTexture    and minBtn:GetNormalTexture())
        tint(minBtn.GetPushedTexture    and minBtn:GetPushedTexture())
        tint(minBtn.GetHighlightTexture and minBtn:GetHighlightTexture())
        tint(minBtn.GetDisabledTexture  and minBtn:GetDisabledTexture())
        if minBtn.GetRegions then
            for _, rg in ipairs({ minBtn:GetRegions() }) do
                if rg:GetObjectType() == "Texture" then tint(rg) end
            end
        end
    end

    local text = header.Text
    if text then
        if EQT.Cfg("accentHeaders") then
            local r, g, b = GetAccent()
            text:SetTextColor(r, g, b)
        else
            text:SetTextColor(1, 1, 1)
        end
        StyleFontString(text)
    end

    -- Catch any other FontString regions on the header (subtitle, count text).
    StyleAllFontStrings(header)

    -- Accent-colored 1px divider beneath the header.
    EnsureAccentDivider(header)

    -- Click-anywhere-on-header overlay: forwards clicks to SetCollapsed so
    -- clicking the title text (not just the +/- button) toggles the
    -- section. The overlay is our own frame; we own its mouse state and
    -- never touch Blizzard's frames' mouse state. Stops short of the
    -- MinimizeButton so that button's native click still fires normally.
    if not _headerClickOverlays[header] then
        local overlay = CreateFrame("Button", nil, header)
        overlay:SetFrameLevel(header:GetFrameLevel() + 1)
        overlay:RegisterForClicks("LeftButtonUp")
        overlay:SetPoint("TOPLEFT",     header, "TOPLEFT",     0, 0)
        local minBtn = header.MinimizeButton
        if minBtn then
            overlay:SetPoint("BOTTOMRIGHT", minBtn, "BOTTOMLEFT", -2, 0)
        else
            overlay:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
        end
        overlay:SetScript("OnClick", function()
            -- Simulate a click on the MinimizeButton so Blizzard's full
            -- collapse cascade runs (header state + tracker layout pass).
            if header.MinimizeButton and header.MinimizeButton.Click then
                header.MinimizeButton:Click("LeftButton")
            elseif header.ToggleCollapsed then
                header:ToggleCollapsed()
            end
        end)
        _headerClickOverlays[header] = overlay
    end
end

-------------------------------------------------------------------------------
-- Block skin: color quest title gold, objectives gray, completed green.
-- Objective lines live on block.lines[*] keyed by text; tint each line's
-- FontString according to its completion state each refresh via a hook on
-- the block's GetLine / AddObjective path where available.
-------------------------------------------------------------------------------
local function StyleObjectiveLine(line)
    if not line or not line.Text then return end
    StyleObjectiveFS(line.Text)
    if line.Dash then StyleObjectiveFS(line.Dash) end
    if line.GetRegions then StyleAllFontStrings(line) end
end

-------------------------------------------------------------------------------
-- Quest type icon system. Replaces Blizzard's per-block type icon with our
-- own atlas picks so the visuals match the rest of EUI.
-------------------------------------------------------------------------------
local QUEST_ICON_ATLAS = {
    normal    = nil,
    campaign  = "Crosshair_campaignquest_32",
    legendary = "Crosshair_legendaryquest_32",
    important = "Crosshair_important_48",
    recurring = "Crosshair_Recurring_48",
    daily     = "Crosshair_Recurring_48",
    weekly    = "Crosshair_Recurring_48",
    meta      = "Crosshair_Wrapper_48",
}
local QUEST_TURNIN_ATLAS = {
    campaign  = "Crosshair_campaignquestturnin_32",
    legendary = "Crosshair_legendaryquestturnin_32",
    important = "Crosshair_importantturnin_48",
    recurring = "Crosshair_Recurringturnin_48",
    daily     = "Crosshair_Recurringturnin_48",
    weekly    = "Crosshair_Recurringturnin_48",
    meta      = "Crosshair_Wrapperturnin_48",
}
local QUEST_ICON_SIZE_OVERRIDE = {
    recurring = 18, daily = 18, weekly = 18, important = 22,
}
local QUEST_ICON_SIZE = 16

-- Cache of questID -> { key = "...", done = bool }. Computed ONCE per quest
-- the first time we see it, then refreshed only when the quest log itself
-- signals change (via QUEST_LOG_UPDATE / QUEST_REMOVED handled below).
-- Never called inline on the live skin path so secure quest-log APIs
-- can't leak taint into MoneyFrame / reward rendering on quest turn-in.
local _classifyCache = {}

local function _computeClassification(questID)
    if not questID or not C_QuestLog then return nil end
    local logIdx = C_QuestLog.GetLogIndexForQuestID
        and C_QuestLog.GetLogIndexForQuestID(questID)
    local info = logIdx and C_QuestLog.GetInfo and C_QuestLog.GetInfo(logIdx)
    local cls  = info and info.questClassification
    local freq = (info and info.frequency) or 0
    local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) or false

    local key = "normal"
    if C_CampaignInfo and C_CampaignInfo.IsCampaignQuest
       and C_CampaignInfo.IsCampaignQuest(questID) then
        key = "campaign"
    elseif cls and Enum and Enum.QuestClassification then
        local QC = Enum.QuestClassification
        if     cls == QC.Important then key = "important"
        elseif cls == QC.Legendary then key = "legendary"
        elseif cls == QC.Campaign  then key = "campaign"
        elseif cls == QC.Recurring then key = "recurring"
        end
    end
    if key == "normal" then
        if     freq == 1 then key = "daily"
        elseif freq == 2 then key = "weekly"
        end
    end
    return { key = key, done = done }
end

local function ClassifyQuest(questID)
    if not questID then return nil, false end
    local entry = _classifyCache[questID]
    if not entry then return nil, false end
    local key = entry.key
    if entry.done and QUEST_TURNIN_ATLAS[key] then
        return QUEST_TURNIN_ATLAS[key], key
    end
    return QUEST_ICON_ATLAS[key], key
end

-- Refresh the classify cache outside any skin / tracker-Update chain.
-- Only driven by quest-log events so secure-API reads never happen inside
-- the debounced tracker Update or block hover paths that surround
-- MoneyFrame / reward rendering.
local function _refreshClassifyCache()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    local seen = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
        local qID = info and info.questID
        if qID then
            seen[qID] = true
            _classifyCache[qID] = _computeClassification(qID)
        end
    end
    -- Drop stale entries for quests no longer in the log (turned in, etc.)
    for qID in pairs(_classifyCache) do
        if not seen[qID] then _classifyCache[qID] = nil end
    end
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("QUEST_LOG_UPDATE")
    f:RegisterEvent("QUEST_ACCEPTED")
    f:RegisterEvent("QUEST_REMOVED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    local _pending = false
    f:SetScript("OnEvent", function()
        if _pending then return end
        _pending = true
        C_Timer.After(0.25, function()
            _pending = false
            _refreshClassifyCache()
        end)
    end)
    if not EQT._eventFrames then EQT._eventFrames = {} end
    if not EQT._eventRegistrations then EQT._eventRegistrations = {} end
    local idx = #EQT._eventFrames + 1
    EQT._eventFrames[idx] = f
    EQT._eventRegistrations[idx] = {"QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_ENTERING_WORLD"}
end

-- Hides Blizzard's built-in quest type icon(s) on a block (without
-- recursing into the block's children) and stamps ours on top.

local function ApplyQuestTypeIcon(block)
    if not block then return end

    -- "Show Quest Icons" on: Blizzard's native icons are shown instead, so
    -- never stamp our own custom icon (hide any we already created).
    if EQT.Cfg("showQuestIcons") then
        if _blockIcons[block] then _blockIcons[block]:Hide() end
        return
    end

    local qID = block.id
    if type(qID) ~= "number" then
        if _blockIcons[block] then _blockIcons[block]:Hide() end
        return
    end

    -- Suppress our custom icon when Blizzard's ItemButton or
    -- groupFinderButton is already visible on this block. Probe the block
    -- fields directly (the icon you SEE is Blizzard's, and our overlay
    -- texture is mouse-pass-through, so it eats the visual click target).
    local hasItem = (block.ItemButton and block.ItemButton.IsShown
                     and block.ItemButton:IsShown())
                 or (block.itemButton and block.itemButton.IsShown
                     and block.itemButton:IsShown())
    local hasLFG  = (block.groupFinderButton and block.groupFinderButton.IsShown
                     and block.groupFinderButton:IsShown())
                 or (block.GroupFinderButton and block.GroupFinderButton.IsShown
                     and block.GroupFinderButton:IsShown())
                 or (block.rightEdgeFrame and block.rightEdgeFrame.IsShown
                     and block.rightEdgeFrame:IsShown())
    if hasItem or hasLFG then
        if _blockIcons[block] then _blockIcons[block]:Hide() end
        return
    end

    local atlas, key = ClassifyQuest(qID)
    if not atlas then
        if _blockIcons[block] then _blockIcons[block]:Hide() end
        return
    end

    local ico = _blockIcons[block]
    if not ico then
        ico = block:CreateTexture(nil, "OVERLAY")
        ico:SetPoint("TOPRIGHT", block, "TOPRIGHT", -2, 3)
        _blockIcons[block] = ico
    end
    -- Skip redundant SetAtlas/SetSize when the icon already matches.
    if ico._lastAtlas ~= atlas then
        ico._lastAtlas = atlas
        local size = QUEST_ICON_SIZE_OVERRIDE[key] or QUEST_ICON_SIZE
        ico:SetSize(size, size)
        ico:SetAtlas(atlas)
    end
    ico:SetAlpha(1)
    ico:Show()
end

-------------------------------------------------------------------------------
-- Focus highlight: color the super-tracked quest's block with the user's
-- focus color (default purple). One texture per block, cached in _blockFocus.
-------------------------------------------------------------------------------
-- Find the quest title FontString on a block. It's the first FontString
-- region in Blizzard's layout (confirmed via dump). Cached per-block so
-- hot paths (hover reassert) don't re-walk regions on every mouse event.
local _blockTitleFSCache = setmetatable({}, { __mode = "k" })
local function GetBlockTitleFS(block)
    if not block then return nil end
    local cached = _blockTitleFSCache[block]
    if cached then return cached end
    if not block.GetRegions then return nil end
    for _, rg in ipairs({ block:GetRegions() }) do
        if rg.GetObjectType and rg:GetObjectType() == "FontString" then
            _blockTitleFSCache[block] = rg
            return rg
        end
    end
    return nil
end

-- Super-tracked quest ID cache. Updated only on SUPER_TRACKING_CHANGED so
-- hover handlers don't hit C_SuperTrack.GetSuperTrackedQuestID on every
-- mouse enter/leave.
local _superTrackedID = nil
local function GetSuperTrackedIDCached() return _superTrackedID end
do
    local sf = CreateFrame("Frame")
    sf:RegisterEvent("SUPER_TRACKING_CHANGED")
    sf:RegisterEvent("PLAYER_ENTERING_WORLD")
    sf:SetScript("OnEvent", function(_, event)
        if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
            local id = C_SuperTrack.GetSuperTrackedQuestID()
            _superTrackedID = (id and id ~= 0) and id or nil
        end
        -- Super-tracking assigns a fresh POI button to the block.
        -- Defer one frame so Blizzard's assignment lands first.
        if event == "SUPER_TRACKING_CHANGED" then
            C_Timer.After(0, function()
                if not EQT._SuppressAllPOIs then return end
                EQT._SuppressAllPOIs()
            end)
        end
    end)
    if not EQT._eventFrames then EQT._eventFrames = {} end
    if not EQT._eventRegistrations then EQT._eventRegistrations = {} end
    local idx = #EQT._eventFrames + 1
    EQT._eventFrames[idx] = sf
    EQT._eventRegistrations[idx] = {"SUPER_TRACKING_CHANGED", "PLAYER_ENTERING_WORLD"}
end

-- One-time layout setup for the title fontstring: font, anchors, width.
-- Called once per block from SkinBlock's full pass.
local function SetupTitleLayout(block)
    if not block then return end
    local fs = GetBlockTitleFS(block)
    if not fs then return end
    StyleTitleFS(fs)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
    -- Strip Blizzard's TOPLEFT+TOPRIGHT dual anchor so SetWidth works.
    if fs.GetNumPoints and fs:GetNumPoints() > 0 then
        local point, relTo, relPoint, x, y = fs:GetPoint(1)
        if point then
            fs:ClearAllPoints()
            fs:SetPoint(point, relTo, relPoint, x or 0, y or 0)
        end
    end
    if fs.SetWidth then fs:SetWidth(220) end
end

-- Lightweight color-only refresh. Called on hover (OnEnter/OnLeave) and
-- from the stamped fast-path in SkinBlock.
function ApplyFocusHighlight(block)  -- global to file
    if not block then return end
    local fs = GetBlockTitleFS(block)
    if not fs then return end
    local qID     = (type(block.id) == "number") and block.id or nil
    local isFocus = qID and (qID == GetSuperTrackedIDCached())
    local isDone  = qID and C_QuestLog and C_QuestLog.IsComplete
                    and C_QuestLog.IsComplete(qID)
    local r, g, b
    if isFocus then
        r, g, b = GetFocusRGB()
    elseif isDone then
        r, g, b = GetCompletedRGB()
    else
        r, g, b = GetTitleRGB()
    end
    fs:SetTextColor(r, g, b)
end

-- Skip all skinning work when the tracker is force-hidden (M+, raid, arena).
-- Uses the cached suppression flag only (set by ApplySuppression /
-- UpdateVisibility). No per-call API queries.
local function ShouldSkipSkin()
    return EQT.IsSuppressed and EQT.IsSuppressed()
end

-- Hook block line-add APIs once per block instance. Catches every line
-- Blizzard creates or recycles without walking children.
local function HookBlockLineMethods(block)
    if _hookedBlocks[block] then return end
    _hookedBlocks[block] = true

    -- Blizzard changes the title text color on mouse enter (darkens it
    -- as hover feedback). Reassert our color from a post-hook so whatever
    -- gold/focus color we chose is what the player sees.
    local function reassertTitle()
        ApplyFocusHighlight(block)
    end
    if block.HookScript then
        block:HookScript("OnEnter", reassertTitle)
        block:HookScript("OnLeave", reassertTitle)
    end
    -- The HeaderButton (if present) often owns the hover script directly.
    if block.HeaderButton and block.HeaderButton.HookScript then
        block.HeaderButton:HookScript("OnEnter", reassertTitle)
        block.HeaderButton:HookScript("OnLeave", reassertTitle)
    end

    -- REMOVED: an OnClick post-hook here used to call
    -- C_SuperTrack.SetSuperTrackedQuestID(block.id) so a left-click also
    -- super-tracked the quest. Setting the super-track from addon (tainted)
    -- execution taints Blizzard's world-map super-track / AreaPOI refresh,
    -- surfacing later as a blocked Frame:SetPropagateMouseClicks() when the map
    -- builds POI pins (ADDON_ACTION_BLOCKED via QuestMapFrame_ShowQuestDetails).
    -- Blizzard's native block click already super-tracks the quest securely, so
    -- the hook was redundant; the focus highlight still follows the super-track
    -- via the SUPER_TRACKING_CHANGED handler.

    -- AddObjective / SetStringText hooks REMOVED (session 68 perf audit).
    -- SkinBlock already styles all fontstrings via GetRegions() walk +
    -- ProcessBlockChildren. These per-call hooks charged Blizzard's entire
    -- AddObjective/SetStringText execution to our addon in the profiler
    -- (11 + 14 = 25 calls per collapse, ~8ms attributed to us).
end

-- Ornamental atlas keywords: textures with these substrings in their atlas
-- name are decorative and should be hidden. Lookup table avoids 9x string.find.
local ORNAMENTAL_KEYWORDS = {
    evergreen = true, toast = true, filigree = true, parchment = true,
    bountiful = true, shimmer = true, sparkle = true, trackerheader = true,
    jailerstower = true,
}
local _ornamentalCache = setmetatable({}, { __mode = "k" })
local function IsOrnamentalAtlas(rg)
    local cached = _ornamentalCache[rg]
    if cached ~= nil then return cached end
    local atlas = rg.GetAtlas and rg:GetAtlas()
    if type(atlas) ~= "string" then _ornamentalCache[rg] = false; return false end
    local l = atlas:lower()
    for kw in pairs(ORNAMENTAL_KEYWORDS) do
        if l:find(kw, 1, true) then _ornamentalCache[rg] = true; return true end
    end
    _ornamentalCache[rg] = false
    return false
end

-- Walk child frames of a block up to 3 levels deep. Strip ornamental
-- atlas textures and style objective fontstrings. Defined at file scope
-- so it's not recreated per SkinBlock call.
local function ProcessBlockChildren(frame, depth)
    if not frame or depth > 3 or not frame.GetChildren then return end

    for _, child in ipairs({ frame:GetChildren() }) do
        if child.GetObjectType then
            local ok, otype = pcall(child.GetObjectType, child)
            if ok then
                if (otype == "Frame" or otype == "Button")
                       and not child.Tooltip then
                    if child.GetRegions then
                        for _, rg in ipairs({ child:GetRegions() }) do
                            local ot = rg.GetObjectType and rg:GetObjectType()
                            if ot == "Texture" then
                                if IsOrnamentalAtlas(rg) then rg:SetTexture("") end
                            elseif ot == "FontString" then
                                StyleObjectiveFS(rg)
                            end
                        end
                    end
                    ProcessBlockChildren(child, depth + 1)
                end
            end
        end
    end

end

-- Weak-keyed so pooled/recycled poiButtons don't leak or get double-hooked.
local _hookedPOIButtons = setmetatable({}, { __mode = "k" })

local function SuppressPOI(block)
    if EQT.Cfg("showQuestIcons") then return end
    local pb = block and block.poiButton
    if not pb then return end
    if pb:IsShown() then pb:Hide() end
    pb:EnableMouse(false)

    -- Re-hide synchronously whenever Blizzard shows this button again (e.g.
    -- on SUPER_TRACKING_CHANGED from clicking a quest) so there's no visible
    -- flash before the next SkinBlock/suppression pass. Hide() only, never
    -- SetParent -- that's the taint-safe version of this pattern (see
    -- InstallShowHook's otf Show-hook above, which does the same thing).
    if not _hookedPOIButtons[pb] then
        _hookedPOIButtons[pb] = true
        hooksecurefunc(pb, "Show", function(self)
            if EQT.Cfg("showQuestIcons") then return end
            self:Hide()
        end)
    end
end

local function SkinBlock(block)
    if not block then return end
    if ShouldSkipSkin() then return end


    -- Suppress POI on every entry -- Blizzard may assign a new pooled
    -- poiButton to the block between skin passes.
    SuppressPOI(block)

    -- Skip blocks already fully skinned. The heavy work (strip textures,
    -- style fontstrings, walk children) only needs to happen once per block.
    -- Quest type icons and focus highlight are cheap and re-applied below.
    if _skinned[block] then
        ApplyQuestTypeIcon(block)
        ApplyFocusHighlight(block)
        return
    end

    HookBlockLineMethods(block)

    -- Raise ItemButton / GroupFinderButton frame levels above the block on
    -- EVERY skin pass. Blizzard pools the block + Init/Reset paths can
    -- lower the level back to the block's, after which clicks fall through
    -- to the block instead of the icon button. Re-applying every pass is
    -- cheap and guarantees correct hit-testing.
    local bl = block.GetFrameLevel and block:GetFrameLevel() or 0
    if block.ItemButton and block.ItemButton.SetFrameLevel then
        block.ItemButton:SetFrameLevel(bl + 5)
    end
    if block.GroupFinderButton and block.GroupFinderButton.SetFrameLevel then
        block.GroupFinderButton:SetFrameLevel(bl + 5)
    end

    -- Strip named decorative textures by key.
    for _, k in ipairs({
        "Background", "HeaderBackground", "Stripe", "Sheen", "Glow",
        "Highlight", "ShineTop", "ShineBottom",
    }) do
        local r = block[k]
        if r and r.SetTexture then r:SetTexture("") end
    end

    -- Single GetRegions() walk: strip remaining textures AND style fontstrings
    -- in one pass instead of two separate walks.
    local myIcon = _blockIcons[block]
    if block.GetRegions then
        for _, rg in ipairs({ block:GetRegions() }) do
            local ot = rg.GetObjectType and rg:GetObjectType()
            if ot == "Texture" then
                if rg ~= myIcon and rg.SetTexture then rg:SetTexture("") end
            elseif ot == "FontString" then
                StyleFontString(rg)
            end
        end
    end

    -- Item button (quest item) count FontString if present.
    if block.itemButton and block.itemButton.Count then
        StyleFontString(block.itemButton.Count)
    end

    -- Replace Blizzard's quest-type icon with ours, based on the quest's
    -- classification / frequency / turn-in state.
    ApplyQuestTypeIcon(block)

    -- One-time title layout (font, anchor strip, width constraint).
    SetupTitleLayout(block)

    -- Focus color for super-tracked / completed / normal quest.
    ApplyFocusHighlight(block)

    -- Strip ornamental textures + style objective fontstrings on child frames.
    ProcessBlockChildren(block, 0)

    _skinned[block] = true

end


-------------------------------------------------------------------------------
-- Re-skin every block a tracker has already populated. Safe to call any time
-- (idempotent via the _eqtBlockSkinned / _eqtBarSkinned flags on each frame).
-------------------------------------------------------------------------------
local function SkinExistingBlocks(tracker)
    if not tracker then return end


    -- Refresh the accent divider under this tracker's header on every pass
    -- so collapsed/re-expanded states always keep a visible divider.
    if tracker.Header then EnsureAccentDivider(tracker.Header) end

    -- Never touch shared-widget-pool trackers' blocks (see SharesWidgetPool).
    -- The header/divider above is safe; the block loop below is not.
    if SharesWidgetPool(tracker) then return end

    -- Collect blocks into an ordered list sorted top-to-bottom by Y. We use
    -- this to apply sequential per-section numbering (1, 2, 3...) that
    -- matches the visual order.
    -- Blizzard's usedBlocks is keyed by template string, and each entry is
    -- a sub-table keyed by blockID -> block. Iterate two levels.
    local ordered = {}
    if tracker.usedBlocks then
        for _, byTemplate in pairs(tracker.usedBlocks) do
            if type(byTemplate) == "table" then
                for _, block in pairs(byTemplate) do
                    if type(block) == "table" and block.GetTop then
                        ordered[#ordered + 1] = block
                    end
                end
            end
        end
        table.sort(ordered, function(a, b)
            local ay = a.GetTop and a:GetTop() or 0
            local by = b.GetTop and b:GetTop() or 0
            return ay > by
        end)

        for _, block in ipairs(ordered) do
            SkinBlock(block)
        end

        -- Style objective lines.
        for _, block in ipairs(ordered) do
            if block.lines then
                for _, line in pairs(block.lines) do
                    StyleObjectiveLine(line)
                end
            end
        end
    end

end

-------------------------------------------------------------------------------
-- Blizzard anchors whichever module currently sits in the top slot with a
-- fixed TOP/TOP offset relative to ObjectiveTrackerFrame. Verified via /dump
-- across QuestObjectiveTracker and ProfessionsRecipeTracker: always -38,
-- independent of module type and independent of Header's height (ruled out
-- separately). We tighten this gap after each layout pass.
-------------------------------------------------------------------------------
local TOP_ANCHOR_OFFSET = -6  -- starting value, tuned by eye
-- Shared with EllesmereUIQuestTracker_Visibility.lua (BG/top-divider offset)
-- so both files derive the top gap from a single source instead of two
-- independent magic numbers drifting apart.
EQT.TOP_ANCHOR_OFFSET = TOP_ANCHOR_OFFSET

-- Reentry guard: TightenTopAnchor's own SetPoint fires the SetPoint hook
-- installed in HookTracker below.
local _tighteningAnchor = false

local function TightenTopAnchor(tracker)
    if _tighteningAnchor then return end
    if not tracker or not tracker.GetPoint or not tracker.SetPoint then return end
    if InCombatLockdown and InCombatLockdown() then return end
    -- Do not interfere during Blizzard's collapse/expand slide animation,
    -- or our SetPoint collides with ObjectiveTrackerSlidingMixin.
    if tracker.IsSliding and tracker:IsSliding() then return end

    local point, relativeTo, relativePoint, xOfs, yOfs = tracker:GetPoint(1)
    if point == "TOP" and relativePoint == "TOP" and relativeTo == _G.ObjectiveTrackerFrame then
        if yOfs and math.abs(yOfs - TOP_ANCHOR_OFFSET) > 0.01 then
            _tighteningAnchor = true
            tracker:SetPoint("TOP", relativeTo, "TOP", xOfs or 0, TOP_ANCHOR_OFFSET)
            _tighteningAnchor = false
        end
    end
end

-------------------------------------------------------------------------------
-- Hook a single sub-tracker.
-------------------------------------------------------------------------------
local function HookTracker(tracker)
    if not tracker then return end
    if _hookedTrackers[tracker] then return end
    _hookedTrackers[tracker] = true

    -- ScenarioObjectiveTracker and UIWidgetObjectiveTracker: only skin the
    -- header. Their child frames (blocks, progress bars, widget containers)
    -- share Blizzard's widget pool with tooltip/AreaPOI widgets. ANY method
    -- call on those frames taints the pool, causing secret-value arithmetic
    -- errors when GameTooltip processes widget sets later (LayoutFrame.lua
    -- "attempt to compare a secret number value" via GameTooltip_ClearWidgetSet).
    if SharesWidgetPool(tracker) then
        if tracker.Header then SkinHeader(tracker.Header) end
        if tracker.Update then
            hooksecurefunc(tracker, "Update", function(self)
                if ShouldSkipSkin() then return end
                if self.Header then EnsureAccentDivider(self.Header) end
                if EQT.QueueResize then EQT.QueueResize() end
            end)
        end
        return
    end

    if tracker.Header then
        SkinHeader(tracker.Header)
        if tracker.Header.SetCollapsed then
            hooksecurefunc(tracker.Header, "SetCollapsed", function(self)
                if ShouldSkipSkin() then return end
            
                SkinHeader(self)
            end)
        end
    end

    if tracker.AddBlock then
        hooksecurefunc(tracker, "AddBlock", function(_, block)
            if ShouldSkipSkin() then return end
        
            if block then _skinned[block] = nil end
            SkinBlock(block)
        end)
    end

    -- tracker.Update hook REPLACED with lightweight dirty flag (session 68).
    -- The old hooksecurefunc charged Blizzard's entire Update() (10 calls
    -- per collapse, full layout pass each) to our addon in the profiler.
    -- Now we just set a flag and defer the work to a single pass.
    local _updateDirty = false
    if tracker.Update then
        hooksecurefunc(tracker, "Update", function()
            if ShouldSkipSkin() or _updateDirty then return end
            _updateDirty = true
            C_Timer.After(0, function()
                _updateDirty = false
                if ShouldSkipSkin() then return end
            
                if tracker.Header then EnsureAccentDivider(tracker.Header) end
                TightenTopAnchor(tracker)
                if EQT.QueueResize then EQT.QueueResize() end
                if tracker.usedBlocks then
                    for _, byTemplate in pairs(tracker.usedBlocks) do
                        if type(byTemplate) == "table" then
                            for _, block in pairs(byTemplate) do
                                if type(block) == "table" then SuppressPOI(block) end
                            end
                        end
                    end
                end
            end)
        end)
    end

    -- ObjectiveTrackerSlidingMixin (SUPER_TRACKING_CHANGED can trigger a
    -- reorder slide, not just collapse/expand) calls tracker:OnEndSlide()
    -- from EndSlide() right after clearing slideInfo -- i.e. exactly when
    -- IsSliding() flips back to false. TightenTopAnchor bails out entirely
    -- while IsSliding() is true (see comment there), so without this hook
    -- the anchor sits at Blizzard's untightened -38 for the ~0.2-0.3s slide
    -- duration and only snaps to TOP_ANCHOR_OFFSET on the next Update() call,
    -- which is what showed up as the whole tracker shifting down briefly on
    -- quest click. Verified against Blizzard_ObjectiveTrackerShared.lua:
    -- EndSlide() -> self.slideInfo = nil -> self:OnEndSlide(...).
    if tracker.OnEndSlide then
        hooksecurefunc(tracker, "OnEndSlide", function(self)
            if ShouldSkipSkin() then return end
            TightenTopAnchor(self)
        end)
    end

    -- Blizzard assigns the top-slot TOP/TOP/-38 anchor at some point AFTER
    -- tracker:Update() returns (GetPoint(1) is still nil inside the Update
    -- hook), and a burst of native Update() passes can re-assign it several
    -- times in quick succession. Hooking SetPoint catches every assignment at
    -- the exact moment it happens and re-tightens synchronously, before the
    -- frame renders -- no visible drop to -38, no polling. _tighteningAnchor
    -- keeps our own SetPoint inside TightenTopAnchor from re-entering the
    -- hook. Combat/slide cases bail inside TightenTopAnchor and are caught
    -- up by the OnEndSlide hook and the deferred Update pass above.
    hooksecurefunc(tracker, "SetPoint", function(self)
        if _tighteningAnchor then return end
        if ShouldSkipSkin() then return end
        TightenTopAnchor(self)
    end)

    -- ContentsFrame:HookScript("OnSizeChanged") REMOVED: HookScript injects
    -- addon code into Blizzard's execution context, tainting ANY secure call
    -- chain that triggers a layout resize (e.g. dropdown menus at M+ end).
    -- The deferred tracker.Update hook + event handlers already call
    -- QueueResize, so this was purely redundant belt-and-suspenders.

    -- Skin blocks that already exist before our hooks were installed.
    -- Run immediately for blocks already populated, then once more
    -- deferred to catch late-populated blocks from Blizzard's init.
    SkinExistingBlocks(tracker)
    C_Timer.After(0.5, function() SkinExistingBlocks(tracker) end)
end

-------------------------------------------------------------------------------
-- Collect every tracker Blizzard exposes. Prefer the authoritative MODULES
-- table on ObjectiveTrackerFrame; fall back to named globals so late-loaded
-- sub-trackers are still caught.
-------------------------------------------------------------------------------
local function EachTracker(fn)
    local seen = {}

    local otf = _G.ObjectiveTrackerFrame
    local modules = otf and (otf.modules or otf.MODULES)
    if modules then
        for _, t in ipairs(modules) do
            if t and not seen[t] then
                seen[t] = true
                fn(t)
            end
        end
    end

    for _, name in ipairs(SUB_TRACKERS) do
        local t = _G[name]
        if t and not seen[t] then
            seen[t] = true
            fn(t)
        end
    end
end

-- Sweep all tracker blocks and suppress any unsuppressed POI buttons.
-- Called from SUPER_TRACKING_CHANGED (deferred) to catch fresh POIs
-- that Blizzard assigns when the player clicks a quest on the map.
EQT._SuppressAllPOIs = function()
    EachTracker(function(tracker)
        -- Shared-widget-pool trackers have no quest POI buttons and touching
        -- their blocks taints the tooltip widget pool (see SharesWidgetPool).
        if SharesWidgetPool(tracker) then return end
        if not tracker.usedBlocks then return end
        for _, byTemplate in pairs(tracker.usedBlocks) do
            if type(byTemplate) == "table" then
                for _, block in pairs(byTemplate) do
                    if type(block) == "table" then SuppressPOI(block) end
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
-- Entry point called from the loader after Blizzard_ObjectiveTracker loads.
-------------------------------------------------------------------------------
function EQT.InitSkin()
    -- Nuke the master "All Objectives" header / menu at the top of the
    -- tracker. We use per-section headers (Quests / Achievements / etc)
    -- instead, so the master bar is redundant.
    local otf = _G.ObjectiveTrackerFrame
    if otf then
        local headerMenu = otf.HeaderMenu
        if headerMenu then
            headerMenu:Hide()
            headerMenu:SetAlpha(0)
            if headerMenu.SetHeight then headerMenu:SetHeight(0.001) end
            headerMenu:HookScript("OnShow", function(self) self:Hide() end)
        end
        if otf.Header and otf.Header ~= headerMenu then
            otf.Header:Hide()
            if otf.Header.SetHeight then otf.Header:SetHeight(0.001) end
            otf.Header:HookScript("OnShow", function(self)
                self:Hide()
                if self.SetHeight then self:SetHeight(0.001) end
            end)
        end
        -- Strip the parchment / nine-slice background behind the whole tracker.
        if otf.NineSlice then otf.NineSlice:Hide() end
        StripTextures(otf)
    end

    EachTracker(HookTracker)

    -- Re-skin on tracker refresh events. Each of these fires when Blizzard
    -- re-populates blocks; we piggy-back to catch newly-pooled-but-not-yet-
    -- hooked children and to reapply fonts/colors Blizzard just reset.
    local evt = CreateFrame("Frame")
    evt:RegisterEvent("QUEST_LOG_UPDATE")
    evt:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    evt:RegisterEvent("SCENARIO_UPDATE")
    evt:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
    evt:RegisterEvent("TRACKED_ACHIEVEMENT_LIST_CHANGED")
    evt:RegisterEvent("TRACKED_RECIPE_UPDATE")
    evt:RegisterEvent("SUPER_TRACKING_CHANGED")
    -- Quest events just need a BG resize. Block skinning is handled by
    -- AddBlock/AddObjective/GetProgressBar/GetTimerBar hooks, so we no
    -- longer need to walk the entire tracker tree on every event.
    evt:SetScript("OnEvent", function(_, event)
        if EQT.QueueResize then EQT.QueueResize() end
        -- Focusing a quest can expand its objective text without Blizzard
        -- relayouting sibling blocks underneath it; force a full relayout
        -- for this event specifically (not the frequent quest-log events,
        -- which already go through Blizzard's own native Update()).
        if event == "SUPER_TRACKING_CHANGED" and EQT.ForceTrackerRelayout then
            EQT.ForceTrackerRelayout()
        end
    end)
    if not EQT._eventFrames then EQT._eventFrames = {} end
    if not EQT._eventRegistrations then EQT._eventRegistrations = {} end
    local idx = #EQT._eventFrames + 1
    EQT._eventFrames[idx] = evt
    EQT._eventRegistrations[idx] = {"QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SCENARIO_UPDATE", "SCENARIO_CRITERIA_UPDATE", "TRACKED_ACHIEVEMENT_LIST_CHANGED", "TRACKED_RECIPE_UPDATE", "SUPER_TRACKING_CHANGED"}

    -- OTF.Update / ObjectiveTracker_Update hooks REMOVED (session 68).
    -- They only called QueueResize, which is already triggered by
    -- the deferred tracker.Update dirty-flag and event handlers above.
    -- Each hooksecurefunc charged Blizzard's full OTF:Update() to us.

    EQT.RestyleAll = function()
        -- Clear skin stamps so the full strip+restyle runs again
        EachTracker(function(t)
            if t.usedBlocks then
                for _, byTemplate in pairs(t.usedBlocks) do
                    if type(byTemplate) == "table" then
                        for _, block in pairs(byTemplate) do
                            if type(block) == "table" then _skinned[block] = nil end
                        end
                    end
                end
            end
            if t.Header then SkinHeader(t.Header) end
            SkinExistingBlocks(t)
        end)
        -- Font/color size changes just resized existing FontStrings in
        -- place; Blizzard's cached block heights are now stale until a
        -- full relayout runs (see EQT.ForceTrackerRelayout above).
        if EQT.ForceTrackerRelayout then EQT.ForceTrackerRelayout() end
    end

    -- Live-update headers, blocks and progress bar fills when the user
    -- changes the UI accent color in Global Settings.
    if EllesmereUI and EllesmereUI.RegAccent then
        EllesmereUI.RegAccent({ type = "callback", fn = function()
            if EQT.RestyleAll then EQT.RestyleAll() end
        end })
    end
end

