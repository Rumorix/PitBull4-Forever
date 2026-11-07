"""Run the actual roster helper with Lua 5.1; no WoW client required."""
from pathlib import Path
import shutil
import subprocess
import unittest


class RaidRoleSanitization(unittest.TestCase):
    def test_roster_roles(self):
        lua = shutil.which("lua5.1")
        if not lua:
            self.skipTest("lua5.1 is not installed")
        source = (Path(__file__).resolve().parents[1] / "GroupHeader.lua").read_text()
        start = source.index("local function build_raid_name_list_without_main_tanks(")
        end = source.index("\nfunction GroupHeader:RefreshGroup(", start)
        fixture = r'''
local secret = {}
function issecretvalue(value) return rawequal(value, secret) end
local MAX_RAID_MEMBERS = 40
local GROUPING_ORDER = {
    ROLE = "MAINTANK,MAINASSIST",
    ASSIGNEDROLE = "TANK,HEALER,DAMAGER,NONE",
}
local roster
function GetNumGroupMembers() return #roster end
function GetRaidRosterInfo(index)
    local r = roster[index]
    return r[1], nil, 1, nil, nil, "MAGE", nil, nil, nil, r[2], nil, r[3]
end
'''
        checks = r'''
local function check(rows, options, expected)
    roster = rows
    assert(build_raid_name_list_without_main_tanks(options) == expected)
end
-- Public main tanks remain excluded; missing roles retain existing behavior.
check({{"Tank", "MAINTANK", "TANK"}, {"Member"}}, {}, "Member")
check({{"Assist", "MAINASSIST", "HEALER"}},
    {group_filter = "MAINASSIST"}, "Assist")
-- A leaked sentinel would match these filter/grouping keys. This tests uses
-- that Lua cannot otherwise trap for ordinary tables (truthiness and indexing).
-- It does not emulate the client's secret-value enforcement.
GROUPING_ORDER.ROLE = "MAINTANK,MAINASSIST"
for _, field in ipairs({2, 3}) do
    local row = {"Unknown"}
    row[field] = secret
    check({row}, {}, "Unknown")
    -- Instrument filter creation to detect a leaked sentinel as a table key.
    local original_tonumber = tonumber
    tonumber = function(token)
        if token == "SECRET" then return secret end
        return original_tonumber(token)
    end
    check({row}, {group_filter = "SECRET"}, "")
    tonumber = original_tonumber
    check({row}, {group_filter = "HEALER"}, "")
end
check({{"Unknown", secret, "HEALER"}}, {group_filter = "HEALER"}, "Unknown")
check({{"Unknown", "MAINTANK", secret}}, {}, "")
for _, grouping in ipairs({"ROLE", "ASSIGNEDROLE"}) do
    check({{"Unknown", secret, secret}, {"Public", "MAINASSIST", "HEALER"}},
        {group_by = grouping}, "Public,Unknown")
end
check({{"Zulu", secret, secret}, {"Alpha"}}, {sort_method = "NAME"}, "Alpha,Zulu")
check({}, {}, nil)
'''
        subprocess.run([lua, "-"], input=fixture + source[start:end] + checks,
                       text=True, check=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
