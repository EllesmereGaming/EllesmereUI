if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local VersionFrame = {}
UI.VersionFrame = VersionFrame

local S, L, P, Tbl
local frame, table_, summaryText

local VISIBLE_ROWS = 15

local function BuildColumns(contentWidth)

    local nameWidth = contentWidth - S.size.SCROLLBAR_W - S.size.SCROLLBAR_GAP - 240
    return {
        {
            key = "name",
            title = T["Player"],


            width = nameWidth,
            value = function(row) return row.name end,
            render = function(cell, row)
                cell.Text:SetText(Ambiguate(row.name, "short"))
                cell.Text:SetTextColor(S.Unpack(S.color.text))
            end,
        },
        {
            key = "installed",
            title = T["Addon"],
            width = 120,
            value = function(row) return row.version and 0 or 1 end,
            render = function(cell, row)
                if row.version then
                    cell.Text:SetText(T["Installed"])
                    cell.Text:SetTextColor(S.Unpack(S.color.text))
                else
                    cell.Text:SetText(T["Not detected"])
                    cell.Text:SetTextColor(S.Unpack(S.color.textFaint))
                end
            end,
        },
        {
            key = "version",
            title = T["Version"],
            width = 120,
            compare = function(a, b)
                if a.version == b.version then return 0 end
                if not a.version then return 1 end
                if not b.version then return -1 end
                return addon.Version:Compare(a.version, b.version)
            end,
            render = function(cell, row)
                if not row.version then
                    cell.Text:SetText("-")
                    cell.Text:SetTextColor(S.Unpack(S.color.textFaint))
                    return
                end

                cell.Text:SetText(addon.Locale.Format(T["v%s"], row.version))
                cell.Text:SetTextColor(S.Unpack(row.behind and S.color.bad or S.color.good))
            end,
        },
    }
end

function VersionFrame:Refresh()
    if not table_ then return end

    local rows = addon.Version:Survey()
    local detected = 0
    for _, row in ipairs(rows) do
        if row.version then detected = detected + 1 end
    end



    Tbl.SetData(table_, rows, true)
    summaryText:SetText(addon.Locale.Format(T["%d of %d detected  ||  Your version: v%s"],
        detected, #rows, addon.Version.OWN))
end


local function Build()
    frame = S.Window("SimpleLootCouncilVersionFrame", "versions", 560, 548,
        T["Raid addon versions"])
    frame:RestorePosition()
    frame.Badge:SetText(S.Colorize(S.color.textMuted,
        addon.Locale.Format(T["v%s"], tostring(addon.Version.OWN))))

    local cursor = L.Cursor(frame.Content)
    cursor:Add(L.Paragraph,
        T["Everyone in the current group is listed. Not detected means no version reply has arrived; it usually means the addon is not installed, but can also mean an older build cannot answer."],
        S.fontHint)
    cursor:Gap(S.size.SECTION)

    table_ = cursor:Add(function(parent, x, _, y)
        local versionTable = Tbl.Create(parent, BuildColumns(frame.Content.slcWidth), VISIBLE_ROWS)
        P.Point(versionTable, "TOPLEFT", parent, "TOPLEFT", x, y)
        return versionTable, versionTable:GetHeight()
    end)
    table_.sortColumn, table_.sortAscending = 1, true

    cursor:Gap(S.size.SECTION)
    local footer = cursor:Add(L.Row, S.size.BTN_H)
    footer:EnableMouse(false)

    summaryText = S.Label(footer, S.fontSmall, "LEFT")
    P.Point(summaryText, "LEFT", footer, "LEFT", 0, 0)
    P.Point(summaryText, "RIGHT", footer, "RIGHT", -150, 0)

    local refresh = S.Button(footer, T["Refresh"], { width = 135 })
    P.Point(refresh, "RIGHT", footer, "RIGHT", 0, 0)
    refresh:SetScript("OnClick", function()
        addon.Version:Poll()
        VersionFrame:Refresh()
    end)



    frame:SetHeight(P.Snap(frame.HeaderHeight + S.size.PAD * 2
        + cursor:Consumed()))

    VersionFrame:Refresh()
    addon.Log:D("UI", "version frame built")
end


local building
local function WhenBuilt(fn)
    if frame then
        fn()
    elseif not building then
        building = true
        S.BuildOnDriver(function()
            building = false
            Build()
            fn()
        end)
    end
end

function VersionFrame:Init()
    S, L, P, Tbl = addon.Style, addon.Layout, addon.Pixel, UI.Table

    addon.Callbacks:Register("VersionChanged", function()
        if frame and frame:IsShown() then VersionFrame:Refresh() end
    end)

    addon.Log:I("UI", "version frame ready")
end

function VersionFrame:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end
    WhenBuilt(function()
        frame:RestorePosition()
        VersionFrame:Refresh()
        frame:Show()
    end)
end
