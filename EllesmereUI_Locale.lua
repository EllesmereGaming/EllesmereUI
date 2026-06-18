--------------------------------------------------------------------------------
--  EllesmereUI_Locale.lua
--  Central multi-language engine for the EllesmereUI options panel, unlock mode,
--  and custom popups/tooltips. In-game gameplay text is intentionally NOT in scope.
--
--  Design: "translate the pixels, never the data." Translation is applied at the
--  render boundary (the :SetText call) inside the shared widget builders, so the
--  English identity fields used for search, page dispatch, and unlock-mode routing
--  keep byte-matching English for free. This file owns only the primitives.
--
--  TIMING: SavedVariables (EllesmereUIDB, which holds the manual language override)
--  are NOT available at file-scope -- they load at ADDON_LOADED. So locale files
--  populate their data unconditionally at load, and the engine resolves the
--  EFFECTIVE locale (client locale + override) and activates the matching catalog
--  at ADDON_LOADED. The options panel renders much later, so this is always in time.
--
--  Zero rendering impact on English: when the effective locale is enUS/enGB,
--  the active catalog is nil and L/Lf/EnKey return the input unchanged, so every
--  :SetText receives byte-identical text. (Locale tables still load into memory,
--  but they are never read on an English client.)
--------------------------------------------------------------------------------
-- ============================================================================
--  [fork] NOTE — this file is a Korean-localization fork of the upstream
--  EllesmereUI_Locale.lua. Everything above this banner is upstream-original.
--  Fork changes are marked inline:
--    * "[fork] MODIFIED" — an upstream function/line we changed (original shown).
--    * "[fork] ADDED" ... "end ADDED" — blocks not present upstream
--      (reverse-format engine, render-boundary hooks, localized tooltip parser).
--  NOTE: the ADDED blocks are language-NEUTRAL — they translate at the render
--  boundary for ANY active locale, not just Korean. Only Locales/koKR.lua is
--  Korean-specific. (Suitable as a general engine enhancement, not a koKR hack.)
--  Upstream code/comments are otherwise left untouched.
-- ============================================================================
local ADDON_NAME = ...

EllesmereUI = EllesmereUI or {}
local EllesmereUI = EllesmereUI

local type, tonumber, pairs, select = type, tonumber, pairs, select
local GetLocale = GetLocale
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame

local SUPPORTED = {
    enUS = true, deDE = true, esES = true, esMX = true, frFR = true,
    itIT = true, ptBR = true, ruRU = true, koKR = true, zhCN = true, zhTW = true,
}

-- Per-locale translation tables, keyed by locale code. Filled at load by the
-- Locales/<code>.lua files via RegisterLocale(). The active one is selected later.
local localeData = {}

-- The currently active translation table (nil = English / identity), and the
-- reverse (translation -> English) map used by EnKey. Both are (re)assigned by
-- Activate(); L/EnKey close over these upvalues so they always see the latest.
local activeCatalog = nil
local reverse = {}
-- [fork] ADDED: reverse-format template lists (built in Activate, used by the render hooks below).
local numTemplates = {}   -- reverse-format templates carrying a numeric capture (rebuilt in Activate)
local strTemplates = {}   -- reverse-format templates with only string (.-) captures (rebuilt in Activate)

--------------------------------------------------------------------------------
--  Translation API
--------------------------------------------------------------------------------

-- The translator. Identity when no catalog is active (English, or before the
-- catalog is resolved). Otherwise looks up the English key; guards short-circuit
-- anything that must never be translated (non-strings, empty, secret combat
-- values, pure numbers, letterless strings like hex/coords) before the lookup.
local function L(s)
    local cat = activeCatalog
    if not cat then return s end
    if type(s) ~= "string" or s == "" then return s end
    if issecretvalue and issecretvalue(s) then return s end
    if tonumber(s) ~= nil then return s end
    if not s:find("%a") then return s end
    local v = cat[s]
    if type(v) == "string" then return v end
    return s   -- untranslated key -> silent English fallback
end
EllesmereUI.L = L

-- Format helper for the hard-case long tail. Uses WoW positional %1$s / %2$d
-- specifiers so translators can reorder placeholders for other word orders.
-- vvv [fork] MODIFIED from upstream: also L() each argument so a label passed
--     as a %s placeholder shows its localized form. Upstream original was:
--         local t = L(s)
--         if type(t) ~= "string" or select("#", ...) == 0 then return t end
--         return t:format(...)
EllesmereUI.Lf = function(s, ...)
    local t = L(s)
    local n = select("#", ...)
    if type(t) ~= "string" or n == 0 then return t end
    local a = { ... }
    for i = 1, n do a[i] = L(a[i]) end
    return t:format(unpack(a, 1, n))
end
-- ^^^ [fork] end MODIFIED

-- Reverse-map identity primitive. Where code reads a rendered FontString back
-- and compares it to an English literal, EnKey maps the on-screen translation
-- back to English so the comparison still matches. Identity on English.
EllesmereUI.EnKey = function(s)
    if type(s) ~= "string" then return s end
    return reverse[s] or s
end

-- Entry point every Locales/<code>.lua file calls. Returns the per-locale table
-- to populate. Files load before the override is known, so EVERY locale file
-- populates its own table; the engine selects the active one at ADDON_LOADED.
EllesmereUI.RegisterLocale = function(code)
    local t = localeData[code]
    if not t then t = {}; localeData[code] = t end
    return t
end

--------------------------------------------------------------------------------
--  Resolve + activate the effective locale
--------------------------------------------------------------------------------
local function GlyphFont(locale)
    -- Simplified Chinese and Traditional Chinese use different system fonts:
    -- zhCN renders with the Simplified glyph set (ARKai_T), zhTW with the
    -- Traditional glyph set (bLEI00D). Routing zhTW to ARKai_T would show
    -- Simplified glyph forms to a Traditional reader, so keep them separate.
    if locale == "zhCN" then return "Fonts\\ARKai_T.ttf"
    elseif locale == "zhTW" then return "Fonts\\bLEI00D.ttf"
    elseif locale == "koKR" then return "Fonts\\2002.TTF"
    elseif locale == "ruRU" then return "Fonts\\FRIZQT___CYR.TTF" end
    return nil
end

-- ============================================================================
-- vvvvv  [fork] ADDED — not in upstream  vvvvv
--   Reverse-format engine: lets format()/concat panels localize from the catalog.
-- ============================================================================
--------------------------------------------------------------------------------
--  Reverse-format fallback support (used by the render-boundary hook below).
--  Some panels render an ALREADY-formatted string (e.g. "96 Items") that the
--  catalog cannot match directly. From catalog keys that carry numeric printf
--  placeholders ("%d Items" -> its localized form) we precompile a Lua pattern, so
--  the hook can recover the numbers from the on-screen string and re-emit the
--  localized template -- letting panels that build text via format()/concat
--  localize purely from the locale file. Keys with %s are skipped (a string
--  capture is ambiguous); a key must also contain an alphabetic literal so the
--  generated pattern stays specific and can't match arbitrary text.
--------------------------------------------------------------------------------
-- Printf-spec scanners. NUM_SPEC = numeric placeholders only (%d, %.2f, ...);
-- PCT_SPEC = same plus %s, used by FillTemplate so both color and number slots
-- get filled in template order.
local NUM_SPEC = "%%[%-+ #0-9%.]*[diouxXeEfgG]"
local PCT_SPEC = "%%[%-+ #0-9%.]*[diouxXeEfgGs]"

-- Pattern matching a Blizzard inline color hex token, |cAARRGGBB. Used when a
-- catalog key carries "%s<numeric>" (color tag glued to a number, e.g. the
-- calculator's "Current iLvl: %s%.1f|r"). A standalone %s (not before a number)
-- becomes a lazy (.-) capture, but ONLY when a literal precedes it so the pattern
-- stays anchored; a %s at the very start of a key is skipped as too ambiguous.
-- %s captures are translated via L() on fill (color tags / unknown text pass
-- through as identity).
local COLOR_CAP = "(|c%x%x%x%x%x%x%x%x)"

-- Compiles catalog keys carrying printf specs into anchored Lua patterns. Returns
-- two lists: numT (templates with a numeric capture) and strT (templates whose only
-- captures are string (.-) ). They are kept apart so the render hook can gate the
-- numeric ones behind a cheap digit test while still trying string templates on text
-- that has no digit (e.g. "Already on <bar>").
local MIN_STR_ANCHOR = 6   -- a (.-) capture is loose; require this many literal chars so it stays anchored
local function BuildTemplates(cat)
    local numT, strT = {}, {}
    if type(cat) ~= "table" then return numT, strT end
    for k, v in pairs(cat) do
        if type(k) == "string" and type(v) == "string" and k:find("%a") then
            local parts, hasNum, hasStr, ok, pos, n, litLen = {}, false, false, true, 1, #k, 0
            while pos <= n do
                if k:byte(pos) == 37 then                       -- '%'
                    if k:byte(pos + 1) == 37 then               -- '%%' -> literal percent
                        parts[#parts + 1] = "%%"; pos = pos + 2; litLen = litLen + 1
                    else
                        local spec = k:match("^" .. PCT_SPEC, pos)
                        if not spec then ok = false; break end  -- malformed -> skip
                        if spec:byte(-1) == 115 then            -- '%s'
                            local nextNum = k:match("^" .. NUM_SPEC, pos + #spec)
                            if nextNum then
                                parts[#parts + 1] = COLOR_CAP   -- inline color: %s glued before a number (always paired with that number)
                            else
                                parts[#parts + 1] = "(.-)"; hasStr = true   -- general string capture
                            end
                            pos = pos + #spec
                        else                                    -- numeric spec
                            parts[#parts + 1] = "(%-?%d+%.?%d*)"; hasNum = true; pos = pos + #spec
                        end
                    end
                else
                    local c = k:sub(pos, pos)
                    if c:find("^[%^%$%(%)%.%[%]%*%+%-%?]$") then parts[#parts + 1] = "%" .. c
                    else parts[#parts + 1] = c end
                    pos = pos + 1; litLen = litLen + 1
                end
            end
            -- A string capture is far looser than a numeric one, so a template that
            -- relies on (.-) must carry a substantial literal anchor; numeric-only
            -- templates are self-anchoring and need no minimum.
            if ok and (hasNum or hasStr) and not (hasStr and litLen < MIN_STR_ANCHOR) then
                local entry = { pat = "^" .. table.concat(parts) .. "$", val = v }
                if hasNum then numT[#numT + 1] = entry else strT[#strT + 1] = entry end
            end
        end
    end
    return numT, strT
end

-- Substitutes captured values (color hex, then numbers, in template order) back
-- into the localized value template. Round-trips literal "%%" via \2 so it isn't
-- consumed by the spec-scanner mid-pass, then restored to a single "%" at the end.
local function FillTemplate(val, caps)
    local i = 0
    local s = val:gsub("%%%%", "\2")
    s = s:gsub(PCT_SPEC, function(spec)
        i = i + 1
        local c = caps[i] or ""
        if spec:byte(-1) == 115 then                    -- %s
            if spec:match("%.0+s$") then return "" end  -- printf %.0s emits nothing (catalog idiom to swallow a plural "s")
            return L(c)                                 -- translate; color tags / non-catalog text pass through unchanged
        end
        return c
    end)
    s = s:gsub("\2", "%%")
    return s
end
-- ^^^^^  [fork] end ADDED (reverse-format engine)  ^^^^^

local function Activate()
    local client = GetLocale()
    if client == "enGB" then client = "enUS" end
    if not SUPPORTED[client] then client = "enUS" end

    -- Manual override (global saved var; nil/unavailable falls back to client).
    local override = EllesmereUIDB and EllesmereUIDB.displayLocale
    if override == "auto" or not SUPPORTED[override or ""] then override = nil end

    local locale = override or client
    EllesmereUI.LOCALE     = locale
    EllesmereUI.IS_ENGLISH = (locale == "enUS")
    EllesmereUI._localeFont = GlyphFont(locale)

    reverse = {}
    if locale == "enUS" then
        activeCatalog = nil
    else
        local src = localeData[locale]
        if src then
            -- Resolve the "= true" keep-English sentinel and build the reverse map.
            for k, v in pairs(src) do
                if v == true then src[k] = k; v = k end
                if type(v) == "string" then reverse[v] = k end
            end
        end
        activeCatalog = src   -- nil if no locale file shipped for this code
    end
    numTemplates, strTemplates = BuildTemplates(activeCatalog)   -- [fork] ADDED
end

-- Preliminary pass at file-load: SavedVariables are not loaded yet, so this
-- resolves the CLIENT locale only and sets the glyph font for EllesmereUI.lua
-- (which reads EllesmereUI._localeFont at its own file-load). The active catalog
-- is filled at ADDON_LOADED below, once the locale files have populated and the
-- override is readable.
Activate()

-- Re-resolve once SavedVariables (the override) are available and every locale
-- file has populated. Nothing renders before this point.
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, loaded)
    if loaded == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        Activate()
    end
end)

-- ============================================================================
-- vvvvv  [fork] ADDED — not in upstream  vvvvv
--   Render-boundary translation hooks (FontString/Button:SetText,
--   SetFormattedText, tooltip line pools, EUI StaticPopup). Catalog hits only.
-- ============================================================================
--------------------------------------------------------------------------------
--  Render-boundary fallback for fontstrings created OUTSIDE the shared widget
--  builders (custom menus, the damage-meter window, raid-frame panels, etc.).
--  Same rule as the builders -- translate at the :SetText render boundary,
--  catalog hits only -- so English, game data, and Blizzard text stay
--  byte-identical (zero impact when no catalog is active). Secret combat values
--  and Blizzard secure frames (StaticPopup, dropdowns, protected/forbidden) are
--  skipped so protected execution paths are never tainted.
--------------------------------------------------------------------------------
do
    local fsProto    = getmetatable(UIParent:CreateFontString(nil, "BACKGROUND")).__index
    local rawSetText = fsProto.SetText
    local busy       = setmetatable({}, { __mode = "k" })

    -- Soft secure guard: skip forbidden frames + Blizzard popups/dropdowns.
    -- IsProtected is intentionally NOT called -- in 12.0 restricted contexts it can
    -- return a secret value, which would taint the comparison and error the hook on
    -- every SetText. Secret text is already skipped; the name check covers popups.
    -- (EUI-owned StaticPopups are handled separately via the StaticPopup_Show hook
    -- below, which translates them with rawSetText -- bypassing this guard.)
    local function isSecure(region)
        local r = region
        for _ = 1, 6 do
            if not r then return false end
            if r.IsForbidden and r:IsForbidden() then return true end
            local n = r.GetName and r:GetName()
            if type(n) == "string" and (n:find("StaticPopup") or n:find("DropDownList")) then return true end
            r = r.GetParent and r:GetParent() or nil
        end
        return false
    end

    -- Resolve ONE string to its translation, or nil if there is no catalog hit.
    -- Tried in order; every step is language-neutral (only a catalog hit changes text):
    --   1) exact catalog lookup (L)
    --   2) reverse-format -- an already-formatted string ("96 Items") matched against
    --      catalog keys carrying placeholders ("%d Items") and re-emitted with the
    --      captured pieces, so format()/concat panels localize from the catalog with no
    --      source edits. Numeric templates are digit-gated; string templates anchored ^...$.
    --   3) inline-color strip -- "|cAARRGGBB<inner>|r" recurses on <inner> so a colored
    --      label hits the bare key, color preserved (anchored ^|c..|r$, multi-color safe)
    --   4) parenthesis strip -- "(<inner>)" recurses on <inner>, parentheses preserved
    --   5) comma list -- "A, B" (e.g. buff-manager "(Echo of Light, Prayer of Mending)")
    --      re-emitted ONLY if EVERY item is a catalog hit, so prose with commas is untouched
    -- Used on the whole string and per line (multi-line widget tooltips).
    local function resolve(s)
        local v = L(s)
        if type(v) == "string" and v ~= s then return v end
        if s:find("%d") then
            for i = 1, #numTemplates do
                local caps = { s:match(numTemplates[i].pat) }
                if caps[1] ~= nil then return FillTemplate(numTemplates[i].val, caps) end
            end
        end
        for i = 1, #strTemplates do
            local caps = { s:match(strTemplates[i].pat) }
            if caps[1] ~= nil then return FillTemplate(strTemplates[i].val, caps) end
        end
        local hex, inner = s:match("^(|c%x%x%x%x%x%x%x%x)(.-)|r$")
        if hex and inner ~= "" then
            local it = resolve(inner)
            if it then return hex .. it .. "|r" end
        end
        local paren = s:match("^%((.-)%)$")
        if paren and paren ~= "" then
            local it = resolve(paren)
            if it then return "(" .. it .. ")" end
        end
        if s:find(", ", 1, true) then
            local parts, n, allOK = {}, 0, true
            for part in (s .. ", "):gmatch("(.-), ") do
                n = n + 1
                local r = resolve(part)
                if r then parts[n] = r else parts[n] = part; allOK = false end
            end
            if allOK and n >= 2 then return table.concat(parts, ", ") end
        end
        return nil
    end

    -- Whole logic guarded so one bad call can never break SetText or spam errors.
    local function translate(self, text)
        if busy[self] then return end
        if type(text) ~= "string" then return end
        if issecretvalue and issecretvalue(text) then return end
        local t = resolve(text)
        -- Multi-line widget tooltips render "Title\n|cff..desc|r" as ONE string via
        -- ShowWidgetTooltip's L(text); split on newlines and resolve() each line so the
        -- existing per-line keys (title + shared "Click to create..." / "Scan..." line)
        -- still apply. Only catalog hits change a line (game/Blizzard text stays put).
        if not t and text:find("\n", 1, true) then
            local changed = false
            local out = text:gsub("[^\n]+", function(line)
                local lt = resolve(line)
                if lt then changed = true; return lt end
                return line
            end)
            if changed then t = out end
        end
        if type(t) ~= "string" or t == text then return end
        if isSecure(self) then return end
        busy[self] = true
        rawSetText(self, t)
        busy[self] = nil
    end

    hooksecurefunc(fsProto, "SetText", function(self, text)
        pcall(translate, self, text)
    end)

    -- SetFormattedText bypasses the SetText hook entirely (separate C method) --
    -- e.g. the Inspect sheet renders "M+ Score: |cff%s%d|r" through it. Re-read
    -- the formatted result and run the same translate() over it. busy[] keeps the
    -- write-back from re-entering.
    hooksecurefunc(fsProto, "SetFormattedText", function(self)
        if busy[self] then return end
        local ok, cur = pcall(self.GetText, self)
        if not ok or type(cur) ~= "string" then return end
        pcall(translate, self, cur)
    end)

    -- Button:SetText is a separate widget method the FontString hook never sees.
    -- Real sightings: ESC game-menu "EUI Unlock Mode", Blizzard Settings panel
    -- "Open EllesmereUI", trainer "Train All". Same guard order as translate()
    -- (secret BEFORE any comparison); write-back must use the Button's own
    -- pre-hook SetText so the hook does not re-fire.
    local btnProto = getmetatable(CreateFrame("Button")).__index
    local rawBtnSetText = btnProto.SetText
    hooksecurefunc(btnProto, "SetText", function(self, text)
        pcall(function()
            if busy[self] then return end
            if type(text) ~= "string" then return end
            if issecretvalue and issecretvalue(text) then return end
            local t = resolve(text)
            if type(t) ~= "string" or t == text then return end
            if isSecure(self) then return end
            busy[self] = true
            rawBtnSetText(self, t)
            busy[self] = nil
        end)
    end)

    -- Tooltip line pools: AddLine/AddDoubleLine-built lines (character-sheet stat
    -- tooltip, item upgrade calc, skinned ilvl lines, etc.) often bypass the
    -- FontString metatable SetText hook in 12.0. Walk the line pool on Show and
    -- run the same translate() over each line -- BOTH columns (AddDoubleLine's
    -- right side lands on <Name>TextRight<i>), and the comparison/ItemRef
    -- tooltips too, which EUI also writes into. busy[] prevents re-entry.
    do
        local SIDES = { "TextLeft", "TextRight" }
        local function scanLines(tt)
            local okN, nm = pcall(tt.GetName, tt)
            if not okN or type(nm) ~= "string" then return end
            local n = tt.NumLines and tt:NumLines() or 0
            for i = 1, n do
                for s = 1, 2 do
                    local fs = _G[nm .. SIDES[s] .. i]
                    if fs then
                        local ok, txt = pcall(fs.GetText, fs)
                        -- Guard secret BEFORE the ~= comparison: GetText() can return a
                        -- secret string in 12.0; comparing it taints/throws (see
                        -- reference_secret_value_pcall). translate() also re-checks.
                        if ok and type(txt) == "string" and not (issecretvalue and issecretvalue(txt)) and txt ~= "" then
                            translate(fs, txt)
                        end
                    end
                end
            end
        end
        for _, tt in ipairs({ _G.GameTooltip, _G.ItemRefTooltip, _G.ShoppingTooltip1, _G.ShoppingTooltip2 }) do
            if tt then
                hooksecurefunc(tt, "Show", function(self) pcall(scanLines, self) end)
            end
        end
    end

    -- StaticPopup translation for EUI-owned dialogs. In 12.0, StaticPopup text is
    -- set through StaticPopup_Show via a path/timing the FontString metatable hook
    -- above does NOT catch, so EUI's own popups (EUI_DELETE_EQUIPMENT_SET, etc.)
    -- render English. We hook StaticPopup_Show and translate the dialog's text +
    -- button labels directly, right after Show. Gated to which:find("^EUI_") so
    -- Blizzard's own popups (and their protected OnAccept paths) are never touched.
    if _G.StaticPopup_Show then
        local function trObj(obj)
            if not (obj and obj.GetText and obj.SetText) then return end
            local ok, cur = pcall(obj.GetText, obj)
            if not ok or type(cur) ~= "string" or cur == "" then return end
            if issecretvalue and issecretvalue(cur) then return end
            local t = resolve(cur)
            if type(t) ~= "string" or t == cur then return end
            if obj.GetObjectType and obj:GetObjectType() == "FontString" then
                busy[obj] = true; rawSetText(obj, t); busy[obj] = nil
            else
                pcall(obj.SetText, obj, t)   -- Button: routes through its own SetText
            end
        end
        hooksecurefunc("StaticPopup_Show", function(which)
            if type(which) ~= "string" or not which:find("^EUI_") then return end
            for i = 1, (_G.STATICPOPUP_NUMDIALOGS or 4) do
                local d = _G["StaticPopup" .. i]
                if d and d.which == which then
                    trObj(d.text or _G["StaticPopup" .. i .. "Text"])
                    for b = 1, 4 do
                        trObj(d["button" .. b] or _G["StaticPopup" .. i .. "Button" .. b])
                    end
                end
            end
        end)
    end

    EllesmereUI._localeRenderHook = true
end
-- ^^^^^  [fork] end ADDED (render-boundary hooks)  ^^^^^

-- ============================================================================
-- vvvvv  [fork] ADDED — not in upstream  vvvvv
--   Localized tooltip-line parser (Item Upgrade Calculator, etc.). Catalog-driven.
-- ============================================================================
--------------------------------------------------------------------------------
--  Localized tooltip-line parsers  (generic engine; data lives in the catalog)
--
--  Some modules scan Blizzard item tooltips for an English literal -- e.g. the
--  Item Upgrade Calculator parses "Upgrade Level: <Track> <r>/<max>". The client
--  localizes that line, so the English match fails on non-English clients and
--  the module silently reads zero. We wrap the affected getter, parse the
--  localized variant, and map the localized track name back to the English key
--  the module is keyed on.
--
--  This engine holds NO language-specific data. Everything comes from the active
--  catalog: the header via L("Upgrade Level"), and each track name via
--  L(<englishKey>) -- with the English track keys read from the module's own data
--  (EUIUpgCalc.Data.trackOrder). A locale enables this purely by translating
--  "Upgrade Level" and the track names in its catalog; no engine edit and no
--  per-locale table. Inert on English / untranslated (L is identity, so the
--  module's own English parse stays in effect).
--------------------------------------------------------------------------------
local function HookUpgradeCalcLocalizedParse()
    if EllesmereUI.IS_ENGLISH then return true end        -- English: the module parses natively
    local C = _G.EUIUpgCalc
    if type(C) ~= "table" or type(C.GetItemTrackAndRank) ~= "function" then return false end
    local header = L("Upgrade Level")
    if header == "Upgrade Level" then return false end    -- catalog not active yet / untranslated: retry
    if C._koLocalizedParseHooked then return true end
    C._koLocalizedParseHooked = true
    local orig = C.GetItemTrackAndRank
    C.GetItemTrackAndRank = function(self, link)
        local t, r = orig(self, link)
        if t then return t, r end                         -- the module's own (English) parse worked
        if not (C_TooltipInfo and type(link) == "string") then return t, r end
        local data = C_TooltipInfo.GetHyperlink(link)
        if not (data and data.lines) then return t, r end
        local tracks = C.Data and C.Data.trackOrder
        if not tracks then return t, r end
        for _, line in ipairs(data.lines) do
            local txt = line.leftText
            if type(txt) == "string" then
                local _, e = txt:find(header, 1, true)     -- plain find (header may be non-ASCII)
                if e then
                    -- Mirrors the module's "%s+(%a+)%s+(%d+)/%d+" parse against the
                    -- text after the localized header; (%S+) because Lua %a doesn't
                    -- match Hangul / CJK. Resolve the captured name to its English
                    -- key by forward-translating the module's own track list.
                    local name, rk = txt:sub(e + 1):match("[:%s]*(%S+)%s+(%d+)/%d+")
                    if name then
                        for _, key in ipairs(tracks) do
                            if L(key) == name then return key, tonumber(rk) end
                        end
                    end
                    break
                end
            end
        end
        return t, r
    end
    return true
end

-- EUIUpgCalc is owned by EllesmereUIQoL, which may load after this engine and
-- after the catalog activates. Try now; otherwise retry on ADDON_LOADED until it
-- succeeds, with PLAYER_LOGIN as the final stop (by then everything is loaded).
if not HookUpgradeCalcLocalizedParse() then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self, ev)
        if HookUpgradeCalcLocalizedParse() or ev == "PLAYER_LOGIN" then self:UnregisterAllEvents() end
    end)
end
-- ^^^^^  [fork] end ADDED (localized tooltip-line parser)  ^^^^^
