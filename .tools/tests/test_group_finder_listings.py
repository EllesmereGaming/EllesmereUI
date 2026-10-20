"""Run the listing presentation logic with Lua 5.1.

Run: python3 .tools/tests/test_group_finder_listings.py
"""
from pathlib import Path
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "EllesmereUIGroupFinder/EUI_GroupFinder_Search.lua").read_text()
HELPERS = SOURCE[SOURCE.index("local function ResultInfo("):SOURCE.index("-- Activity info by activity ID.")]
LOGIC = SOURCE[SOURCE.index("function XF.ListOptionsActive()"):SOURCE.index("-- Result rows and tooltip")]
LUA = shutil.which("lua5.1")

FIXTURE = r'''
local XF, ns = {}, {}
local cfg, infos, members, statuses, pending = {}, {}, {}, {}, {}
local combat, lockdown, deferred, hooks, reads, memberReads, updates = false, false, {}, {}, 0, 0, 0
C_ChatInfo = { InChatMessagingLockdown = function() return lockdown end }
local secret = setmetatable({}, { __index = function() error("indexed secret data") end })
local inaccessible = setmetatable({}, { __index = function() error("indexed inaccessible data") end })
local function IsSecret(v) return rawequal(v, secret) end
function canaccesstable(v) return not rawequal(v, inaccessible) end
local function Cfg() return cfg end
function InCombatLockdown() return combat end
function XF.Defer(key, fn) deferred[key] = fn end
function UnitClass() return "Warrior", "WARRIOR" end
EllesmereUI = { L = function(text) return text end }
ScrollBoxConstants = { RetainScrollPosition = true }
function CreateDataProvider(data)
    return {
        data = data or {},
        Insert = function(self, value) self.data[#self.data + 1] = value end,
        EnumerateEntireRange = function(self) return ipairs(self.data) end,
    }
end
local function Widget()
    return {
        Show = function(self) self.shown = true end,
        SetShown = function(self, shown) self.shown = shown end,
        SetText = function(self, text) self.text = text end,
        SetPoint = function(self, ...) self.point = {...} end,
    }
end
local SP = { results = {}, applications = {}, visible = true }
function SP:IsVisible() return self.visible end
function SP:IsProtected() return self.protected end
function SP:HookScript(event, callback)
    assert(not hooks[event], "installed the same script hook twice")
    hooks[event] = callback
end
SP.ScrollBox = { NoResultsFound = Widget(), StartGroupButton = Widget(), sets = 0 }
function SP.ScrollBox:IsProtected() return self.protected end
function SP.ScrollBox:GetDataProvider() return self.provider end
function SP.ScrollBox:SetDataProvider(provider)
    self.provider = provider
    self.sets = self.sets + 1
end
local originalProvider
function LFGListSearchPanel_UpdateResults(panel)
    updates = updates + 1
    panel.ScrollBox.NoResultsFound.shown = false
    panel.ScrollBox.StartGroupButton.shown = false
    if panel.searching then panel.ScrollBox.provider = nil; return end
    originalProvider = CreateDataProvider()
    for _, id in ipairs(panel.results) do originalProvider:Insert({ resultID = id }) end
    for _, id in ipairs(panel.applications) do originalProvider:Insert({ resultID = id }) end
    if panel.startGroup then originalProvider:Insert({ startGroup = true }) end
    panel.ScrollBox:SetDataProvider(originalProvider)
end
function LFGListSearchPanel_SelectResult(panel, id)
    panel.selectedResult = id
    LFGListSearchPanel_UpdateResults(panel)
end
function LFGListSearchPanel_OnEvent(panel, event, ...)
    if hooks.OnEvent then hooks.OnEvent(panel, event, ...) end
end
function hooksecurefunc(name, callback)
    assert(not hooks[name], "installed the same hook twice")
    hooks[name] = callback
    local original = _G[name]
    _G[name] = function(...)
        original(...)
        callback(...)
    end
end
C_LFGList = {
    GetSearchResultInfo = function(id)
        assert(not IsSecret(id), "passed a secret ID to the API")
        reads = reads + 1
        return infos[id]
    end,
    GetApplicationInfo = function(id)
        assert(not IsSecret(id), "passed a secret ID to the API")
        return id, statuses[id] or "none", pending[id]
    end,
    GetSearchResultPlayerInfo = function(id, index)
        memberReads = memberReads + 1
        return (members[id] or {})[index]
    end,
}
local function Add(id, score, age, classes)
    SP.results[#SP.results + 1] = id
    infos[id] = { leaderOverallDungeonScore = score, age = age, numMembers = #(classes or {}) }
    members[id] = {}
    for _, class in ipairs(classes or {}) do
        members[id][#members[id] + 1] = { classFilename = class }
    end
end
local function IDs()
    local ids = {}
    for _, data in ipairs(SP.ScrollBox.provider.data) do ids[#ids + 1] = data.resultID or "start" end
    return table.concat(ids, ",")
end
'''


@unittest.skipUnless(LUA, "requires lua5.1 on PATH")
class ListingTests(unittest.TestCase):
    def check_lua(self, checks):
        result = subprocess.run(
            [LUA, "-"], input=FIXTURE + HELPERS + LOGIC + checks,
            text=True, capture_output=True, cwd=ROOT,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_off_does_not_hook_refresh_or_query(self):
        self.check_lua('''
            Add(1, 100, 10, {"WARRIOR"})
            XF.EnsureListingHooks(); XF.RefreshListings(); XF.UpdateListings(SP)
            assert(next(hooks) == nil and updates == 0 and reads == 0 and memberReads == 0)
        ''')

    def test_hide_class_checks_every_member_and_preserves_blizzard_data(self):
        self.check_lua('''
            Add(1, 100, 10, {"MAGE", "WARRIOR"})
            Add(2, 200, 20, {"MAGE"})
            Add(3, 300, 30, {"WARRIOR"})
            cfg.hideMyClass = true
            _G._ = "unchanged"
            XF.RefreshListings()
            assert(IDs() == "2" and _G._ == "unchanged")
            assert(table.concat(SP.results, ",") == "1,2,3")
            assert(#originalProvider.data == 3 and originalProvider.data[1].resultID == 1)
            cfg.hideMyClass = false; XF.RefreshListings()
            assert(IDs() == "1,2,3")
        ''')

    def test_applications_stay_visible_and_sort_above_results(self):
        self.check_lua('''
            Add(1, 4000, 5, {"WARRIOR"}); statuses[1] = "applied"
            Add(2, 3000, 2, {"WARRIOR"}); statuses[2] = "invited"
            Add(3, 2000, 1, {"WARRIOR"}); pending[3] = "applied"
            Add(4, 5000, 3, {"MAGE"})
            Add(5, 6000, 4, {"WARRIOR"}); statuses[5] = "declined"
            infos[6] = { numMembers = 1 }; members[6] = {{ classFilename = "WARRIOR" }}
            SP.applications = {6}; statuses[6] = "applied"
            cfg.hideMyClass = true; cfg.sortListings = "score"
            XF.RefreshListings()
            assert(IDs() == "1,2,3,6,4")
            assert(SP.applications[1] == 6 and #SP.results == 5)
        ''')

    def test_false_pending_status_does_not_bypass_class_filter(self):
        self.check_lua('''
            Add(1, 100, 10, {"WARRIOR"}); pending[1] = false
            cfg.hideMyClass = true; XF.RefreshListings()
            assert(IDs() == "")
        ''')

    def test_score_and_age_orders_with_stable_ties_and_missing_values(self):
        self.check_lua('''
            Add(1, 2000, 60); Add(2, 3000, 20); Add(3, 3000, 5); Add(4, nil, nil)
            SP.startGroup = true
            cfg.sortListings = "score"; XF.RefreshListings()
            assert(IDs() == "2,3,1,4,start" and reads == 4 and memberReads == 0)
            cfg.sortListings = "time"; XF.RefreshListings()
            assert(IDs() == "3,2,1,4,start")
            cfg.sortListings = "default"; XF.RefreshListings()
            assert(IDs() == "1,2,3,4,start")
        ''')

    def test_single_result_updates_hide_and_restore_groups_and_resort(self):
        self.check_lua('''
            Add(1, 1000, 10, {"MAGE"}); Add(2, 2000, 20, {"MAGE"})
            cfg.hideMyClass = true; cfg.sortListings = "score"; XF.RefreshListings()
            assert(IDs() == "2,1")
            members[2][1].classFilename = "WARRIOR"
            LFGListSearchPanel_OnEvent(SP, "LFG_LIST_SEARCH_RESULT_UPDATED", 2)
            assert(IDs() == "1")
            members[2][1].classFilename = "MAGE"; infos[1].leaderOverallDungeonScore = 3000
            LFGListSearchPanel_OnEvent(SP, "LFG_LIST_SEARCH_RESULT_UPDATED", 2)
            assert(IDs() == "1,2")
            cfg.hideMyClass = false; cfg.sortListings = "default"; XF.RefreshListings()
            local before = updates
            LFGListSearchPanel_OnEvent(SP, "LFG_LIST_SEARCH_RESULT_UPDATED", 2)
            assert(updates == before)
        ''')

    def test_secret_and_inaccessible_member_data_fails_open(self):
        self.check_lua('''
            Add(1, 100, 10, {"MAGE"}); members[1][1] = secret
            Add(2, 100, 10, {"MAGE"}); members[2][1] = inaccessible
            Add(3, 100, 10, {"MAGE"}); members[3][1].classFilename = secret
            Add(4, 100, 10); infos[4].numMembers = secret
            Add(5, 100, 10); infos[5] = secret
            Add(6, 100, 10); infos[6] = inaccessible
            Add(7, 100, 10); infos[7] = nil
            cfg.hideMyClass = true; XF.RefreshListings()
            assert(IDs() == "1,2,3,4,5,6,7")
            assert(SP.ScrollBox.provider == originalProvider)
        ''')

    def test_secret_sort_keys_are_never_compared(self):
        self.check_lua('''
            Add(1, secret, secret); Add(2, 100, 10); Add(3, 200, 5)
            cfg.sortListings = "score"; XF.RefreshListings()
            assert(IDs() == "3,2,1")
            cfg.sortListings = "time"; XF.RefreshListings()
            assert(IDs() == "3,2,1")
        ''')

    def test_secret_ids_or_application_status_leave_source_unchanged(self):
        self.check_lua('''
            Add(1, 100, 10); Add(2, 200, 20)
            cfg.sortListings = "score"; statuses[1] = secret; XF.RefreshListings()
            assert(SP.ScrollBox.provider == originalProvider and reads == 0)
            statuses[1] = nil; SP.results[1] = secret; XF.RefreshListings()
            assert(SP.ScrollBox.provider == originalProvider and reads == 0)
            SP.ScrollBox.provider = CreateDataProvider({secret})
            XF.UpdateListings(SP)
            assert(SP.ScrollBox.provider.data[1] == secret)
        ''')

    def test_hidden_selection_is_cleared_and_empty_list_explained(self):
        self.check_lua('''
            Add(1, 100, 10, {"WARRIOR"}); SP.selectedResult = 1; SP.startGroup = true
            cfg.hideMyClass = true; XF.RefreshListings()
            assert(SP.selectedResult == nil and IDs() == "")
            assert(SP.ScrollBox.NoResultsFound.shown)
            assert(SP.ScrollBox.NoResultsFound.text == "No groups match your filters.")
            assert(SP.ScrollBox.StartGroupButton.shown)
            assert(SP.ScrollBox.NoResultsFound.point[1] == "TOP")
            cfg.hideMyClass = false; XF.RefreshListings()
            assert(IDs() == "1,start" and not SP.ScrollBox.NoResultsFound.shown)
        ''')

    def test_combat_defers_until_safe_and_respects_latest_settings(self):
        self.check_lua('''
            Add(1, 100, 10, {"WARRIOR"}); cfg.hideMyClass = true; combat = true
            XF.RefreshListings(); XF.RefreshListings()
            assert(updates == 0 and reads == 0 and deferred.listings)
            cfg.hideMyClass = false; combat = false; deferred.listings()
            assert(IDs() == "1")
            cfg.hideMyClass = true; combat = true
            LFGListSearchPanel_UpdateResults(SP)
            assert(IDs() == "1" and reads == 0)
            combat = false; deferred.listings()
            assert(IDs() == "")
        ''')

    def test_chat_lockdown_never_reenters_blizzard_row_initializers(self):
        self.check_lua('''
            Add(1, 100, 10); cfg.sortListings = "score"; lockdown = true
            XF.RefreshListings()
            assert(updates == 0 and reads == 0)
            LFGListSearchPanel_UpdateResults(SP)
            assert(SP.ScrollBox.provider == originalProvider and reads == 0)
            lockdown = false; XF.RefreshListings()
            assert(reads == 1)
        ''')

    def test_protected_hidden_and_searching_panels_are_untouched(self):
        self.check_lua('''
            Add(1, 100, 10); cfg.sortListings = "score"
            SP.protected = true; XF.RefreshListings()
            SP.protected = false; SP.ScrollBox.protected = true; XF.RefreshListings()
            SP.ScrollBox.protected = false; SP.visible = false; XF.RefreshListings()
            assert(updates == 0 and reads == 0)
            SP.visible = true; SP.searching = true; XF.RefreshListings()
            assert(reads == 0 and SP.ScrollBox.provider == nil)
        ''')


if __name__ == "__main__":
    unittest.main()
