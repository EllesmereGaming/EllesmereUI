if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\MirrorTimerPage_Options.lua
--  Resource Bars options: the OTHER BARS section at the bottom of the Cast
--  Bar page (Breath, Fatigue, Feign Death and the countdowns). The bars are
--  drawn like the Player Cast Bar (EUI_ResourceBars_MirrorTimer.lua), so a
--  bar's own settings are its switch and its fill colour.
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
    local function Refresh()
        if _G._ERB_Apply then _G._ERB_Apply() end
        if EllesmereUI.NotifyElementResized then EllesmereUI.NotifyElementResized(ns.MT_UNLOCK_KEY) end
    end

    local function Toggle(K)
        return { type = "toggle", text = K.name,
            tooltip = "Shows this timer on a bar drawn like the Player Cast Bar; Other Bars in Unlock Mode moves them all.",
            getValue = function() local c = C(K.id); return c and c.enabled end,
            setValue = function(v)
                local c = C(K.id); if not c then return end
                c.enabled = v; Refresh(); EllesmereUI:RefreshPage()
            end }
    end

    -- The fill colour swatch, on the bar's half of the row.
    local function Extras(rgn, K)
        if EllesmereUI._prebuilding then return end
        local id = K.id
        EllesmereUI.BuildInlineSwatches(rgn, {
            { tooltip = "Fill Color", hasAlpha = true, disabledTooltip = K.name,
              disabled = function() local c = C(id); return not (c and c.enabled) end,
              getValue = function()
                  local c = C(id); if not c then return 1, 1, 1, 1 end
                  return c.fillR or 1, c.fillG or 1, c.fillB or 1, c.fillA or 1
              end,
              setValue = function(r, g, b, a)
                  local c = C(id); if not c then return end
                  c.fillR, c.fillG, c.fillB, c.fillA = r, g, b, a
                  Refresh()
              end },
        }, { size = 20 })
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
