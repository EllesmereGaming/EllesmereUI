-------------------------------------------------------------------------------
--  EllesmereUI_Startup.lua
--  Early startup hooks that must run before the main UI files.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

EllesmereUI = EllesmereUI or {}

local function NormalizeFCTFontPath(path)
    if type(path) ~= "string" or path == "" or path == "default" then
        return nil
    end

    if path:find("\\media\\fonts\\", 1, true) then
        return path
    end

    local legacyPrefix = "Interface\\AddOns\\EllesmereUI\\media\\"
    if path:sub(1, #legacyPrefix) == legacyPrefix then
        local suffix = path:sub(#legacyPrefix + 1)
        if suffix ~= "" then
            return legacyPrefix .. "fonts\\" .. suffix
        end
    end

    return path
end

local function ApplySavedCombatTextFont()
    if not EllesmereUIDB then return end

    local saved = NormalizeFCTFontPath(EllesmereUIDB.fctFont)
    EllesmereUIDB.fctFont = saved
    if not saved then return end

    _G.DAMAGE_TEXT_FONT = saved

    local fontObj = _G.CombatTextFont
    if fontObj and fontObj.GetFont then
        local _, size, flags = fontObj:GetFont()
        fontObj:SetFont(saved, size or 120, flags or "")
    end
end

EllesmereUI.NormalizeFCTFontPath = NormalizeFCTFontPath
EllesmereUI.ApplySavedCombatTextFont = ApplySavedCombatTextFont

local fctInitFrame = CreateFrame("Frame")
fctInitFrame:RegisterEvent("PLAYER_LOGIN")
fctInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
fctInitFrame:RegisterEvent("ADDON_LOADED")
fctInitFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME and arg1 ~= "Blizzard_CombatText" then
            return
        end
    end

    ApplySavedCombatTextFont()

    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_CombatText" then
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
