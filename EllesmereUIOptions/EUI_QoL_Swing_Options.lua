if EUI_CLIENT_BLOCKED then return end
if not EllesmereUI._ModuleNS["EllesmereUIQoL"] or not _G._EUI_Swing_Profile then return end

_G._EUI_BuildSwingPage = function(_, parent, yOffset)
    local EUI = EllesmereUI
    local W = EUI.Widgets
    local y = yOffset
    parent._showRowDivider = true
    EUI:ClearContentHeader()
    local _, hh = W:SectionHeader(parent, "SWING TIMER", y);  y = y - hh
    local function Get(key) return _G._EUI_Swing_Profile()[key] end
    local function Set(key, value)
        _G._EUI_Swing_Profile()[key] = value
        _G._EUI_Swing_Apply()
    end
    local function Toggle(label, key)
        return { type = "toggle", text = label,
            getValue = function() return Get(key) end,
            setValue = function(v) Set(key, v) end }
    end
    local function Slider(label, key, lo, hi)
        return { type = "slider", text = label, min = lo, max = hi, step = 1,
            getValue = function() return Get(key) end,
            setValue = function(v) Set(key, v) end }
    end
    local _, h = W:DualRow(parent, y,
        Toggle("Enable Swing Timer", "enabled"), Toggle("Only Show In Combat", "combatOnly"))
    y = y - h
    _, h = W:DualRow(parent, y,
        Toggle("Main Hand", "mainHand"), Toggle("Off Hand", "offHand"))
    y = y - h
    _, h = W:DualRow(parent, y,
        Toggle("Ranged", "ranged"), Toggle("Highlight Queued Attacks", "queueColor"))
    y = y - h
    _, h = W:DualRow(parent, y,
        Slider("Width", "width", 100, 600), Slider("Bar Height", "height", 12, 40))
    y = y - h
    _, h = W:DualRow(parent, y,
        Slider("Bar Spacing", "gap", 0, 20), Slider("Text Size", "fontSize", 8, 24))
    y = y - h
    local _, textureNames, textureOrder = EUI.BuildBarTextureTables()
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Bar Texture", values = textureNames, order = textureOrder,
          getValue = function() return Get("texture") end,
          setValue = function(v) Set("texture", v) end },
        { type = "label", text = "Position with Unlock Mode" })
    y = y - h
    return math.abs(y)
end
