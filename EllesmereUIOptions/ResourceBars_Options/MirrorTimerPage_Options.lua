if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\MirrorTimerPage_Options.lua
--  Resource Bars options: the OTHER BARS section at the bottom of the Cast
--  Bar page (Breath, Fatigue, Feign Death and the countdowns). The bars are
--  drawn like the Player Cast Bar (EUI_ResourceBars_MirrorTimer.lua), so a
--  bar's own settings are its switch, its fill colour and, in its cog, the
--  Low Warning.
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
    -- A timer bar's own settings reach only the timer bars: their apply, never
    -- the whole Resource Bars one. resized: the stack's size changed (a bar
    -- turned on or off), so what is anchored to the mover follows.
    local function Refresh(resized)
        ns.MT_Apply()
        if resized then EllesmereUI.NotifyElementResized(ns.MT_UNLOCK_KEY) end
    end
    local function AllOff()
        for _, K in ipairs(kinds) do
            local c = C(K.id)
            if c and c.enabled then return false end
        end
        return true
    end

    local function Toggle(K)
        return { type = "toggle", text = K.name,
            tooltip = "Shows this timer on a bar drawn like the Player Cast Bar; Other Bars in Unlock Mode moves them all.",
            getValue = function() local c = C(K.id); return c and c.enabled end,
            setValue = function(v)
                local c = C(K.id); if not c then return end
                c.enabled = v; Refresh(true); EllesmereUI:RefreshPage()
            end }
    end

    -- The Low Warning cog, nearest the switch, and the fill colour swatch left
    -- of it, on the bar's half of the row.
    local function Extras(rgn, K)
        if EllesmereUI._prebuilding then return end
        local id = K.id
        local off = function() local c = C(id); return not (c and c.enabled) end
        EllesmereUI.BuildInlineCog(rgn, { title = K.name, disabled = off, disabledTooltip = K.name, rows = {
            { type = "toggle", label = "Low Warning",
              tooltip = "The bar turns red and blinks once it runs down to Warn When Left.",
              get = function() local c = C(id); return c and c.lowWarn or false end,
              set = function(v) local c = C(id); if c then c.lowWarn = v; Refresh() end end },
            { type = "slider", label = "Warn When Left", min = 10, max = 90, step = 5,
              tooltip = "When this much of the bar is left, in percent, the bar turns red and blinks.",
              disabled = function() local c = C(id); return not (c and c.lowWarn) end,
              get = function() local c = C(id); return c and c.lowWarnAt or 30 end,
              set = function(v) local c = C(id); if c then c.lowWarnAt = v; Refresh() end end },
        } })
        EllesmereUI.BuildInlineSwatches(rgn, {
            { tooltip = "Fill Color", hasAlpha = true, disabledTooltip = K.name, disabled = off,
              getValue = function()
                  local c = C(id); if not c then return 1, 1, 1, 1 end
                  return c.fillR or 1, c.fillG or 1, c.fillB or 1, c.fillA or 1
              end,
              setValue = function(r, g, b, a)
                  local c = C(id); if not c then return end
                  c.fillR, c.fillG, c.fillB, c.fillA = r, g, b, a
                  Refresh()
              end },
        })
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h
    local hdr
    hdr, h = W:SectionHeader(parent, "OTHER BARS", y);  y = y - h
    -- The one mover of every timer bar; it shows once a bar is on.
    EllesmereUI.BuildSectionUnlockJump(hdr, { key = ns.MT_UNLOCK_KEY, disabled = AllOff, disabledTooltip = "Other Bars" })

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
