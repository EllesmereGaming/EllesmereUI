if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\MirrorTimerPage_Options.lua
--  Resource Bars options: the OTHER BARS section at the bottom of the Cast
--  Bars page (Breath, Fatigue, Feign Death and the countdowns). The bars are
--  drawn like the Player Cast Bar (EUI_ResourceBars_MirrorTimer.lua, View),
--  so a row is a bar's switch and fill colour, and its cog holds what is its
--  own: Low Warning, Hide Blizzard Bar, the golden numbers (countdowns) and
--  Own Size.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not ns then return end  -- module disabled: no options page

-- Builds the section from y; returns the y under it.
function ns.ERB_BuildTimerBarRows(parent, y)
    local kinds = ns.MT_KINDS
    if not (kinds and kinds[1]) then return y end
    local W = EllesmereUI.Widgets
    local DB = ns._ERB_OptEnv.DB
    local _, h

    local function C(id) local p = DB(); return p and p.mirrorTimer and p.mirrorTimer[id] end
    local function Refresh(K)
        if _G._ERB_Apply then _G._ERB_Apply() end
        if EllesmereUI.NotifyElementResized then EllesmereUI.NotifyElementResized(K.unlock) end
    end

    local function Toggle(K)
        return { type = "toggle", text = K.name,
            tooltip = "Your own bar for this timer, drawn like the Player Cast Bar. Move it in Unlock Mode.",
            getValue = function() local c = C(K.id); return c and c.enabled end,
            setValue = function(v)
                local c = C(K.id); if not c then return end
                c.enabled = v; Refresh(K); EllesmereUI:RefreshPage()
            end }
    end

    -- The fill colour swatch and the cog, on the bar's half of the row.
    local function Extras(rgn, K)
        if EllesmereUI._prebuilding then return end
        local id = K.id
        local off = function() local c = C(id); return not (c and c.enabled) end
        local function Get(key, default)
            return function()
                local c = C(id); local v = c and c[key]
                if v == nil then return default end
                return v
            end
        end
        local function Set(key)
            return function(v) local c = C(id); if not c then return end; c[key] = v; Refresh(K) end
        end
        local function noSize() local c = C(id); return not (c and c.ownSize) end

        EllesmereUI.BuildInlineSwatches(rgn, {
            { tooltip = "Fill Color", hasAlpha = true, disabled = off, disabledTooltip = K.name,
              getValue = function()
                  local c = C(id); if not c then return 1, 1, 1, 1 end
                  return c.fillR or 1, c.fillG or 1, c.fillB or 1, c.fillA or 1
              end,
              setValue = function(r, g, b, a)
                  local c = C(id); if not c then return end
                  c.fillR, c.fillG, c.fillB, c.fillA = r, g, b, a
                  Refresh(K)
              end },
        }, { size = 20 })

        local rows = {
            { type = "toggle", label = "Low Warning",
              tooltip = "The bar turns red and blinks once it runs down to Warn When Left.",
              get = Get("lowWarn", false), set = Set("lowWarn") },
            { type = "slider", label = "Warn When Left", min = 10, max = 90, step = 5,
              tooltip = "When this much of the bar is left, in percent, the bar turns red and blinks.",
              disabled = function() local c = C(id); return not (c and c.lowWarn) end,
              get = Get("lowWarnAt", 30), set = Set("lowWarnAt") },
            { type = "toggle", label = "Hide Blizzard Bar",
              tooltip = "Makes Blizzard's own bar for this timer invisible while this one is on.",
              get = function() local c = C(id); return c and c.hideBlizzard ~= false end,
              set = Set("hideBlizzard") },
        }
        -- The countdowns: the bar steps aside for the game's big numbers, as the
        -- game's own bar does, unless this keeps it.
        if K.numbersAt then
            rows[#rows + 1] = { type = "toggle", label = "Show Under the Golden Numbers",
                tooltip = EllesmereUI.Lf("Keeps this bar on screen once the game switches to its big golden numbers (under %d seconds). Off, they show alone, as in the default UI.", K.numbersAt),
                get = Get("showUnderNumbers", false), set = Set("showUnderNumbers") }
        end
        rows[#rows + 1] = { type = "toggle", label = "Own Size",
            tooltip = "This bar's own Width and Height instead of the Player Cast Bar's.",
            get = Get("ownSize", false),
            set = function(v)
                local c, p = C(id), DB(); if not (c and p) then return end
                -- Starts from the size it shows: the cast bar's.
                if v and not c.ownSize then c.width, c.height = p.castBar.width, p.castBar.height end
                c.ownSize = v
                Refresh(K)
            end }
        rows[#rows + 1] = { type = "slider", label = "Width", min = 50, max = 800, step = 1,
            disabled = noSize, get = Get("width", 220), set = Set("width") }
        rows[#rows + 1] = { type = "slider", label = "Height", min = 4, max = 60, step = 1,
            disabled = noSize, get = Get("height", 20), set = Set("height") }

        EllesmereUI.BuildInlineCog(rgn, { title = K.name, disabled = off, disabledTooltip = K.name, rows = rows })
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h
    _, h = W:SectionHeader(parent, "OTHER BARS", y);  y = y - h

    -- Two bars per row.
    for i = 1, #kinds, 2 do
        local L, R = kinds[i], kinds[i + 1]
        local row
        row, h = W:DualRow(parent, y, Toggle(L), R and Toggle(R) or EllesmereUI.BlankRowCfg());  y = y - h
        Extras(row._leftRegion, L)
        if R then Extras(row._rightRegion, R) end
    end
    return y
end
