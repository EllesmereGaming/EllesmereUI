with open("audit_raw.txt", "r") as f:
    lines = f.readlines()

methods = set()
fields = set()

for line in lines:
    if "GetSpellID(" in line or ":GetSpellID" in line: methods.add("GetSpellID")
    if "GetAuraSpellID(" in line or ":GetAuraSpellID" in line: methods.add("GetAuraSpellID")
    if "cooldownID" in line: fields.add("cooldownID")
    if "cooldownInfo" in line: fields.add("cooldownInfo")
    if "itemFramePool" in line: fields.add("itemFramePool")
    if "EnumerateActive" in line: methods.add("EnumerateActive")
    if "GetCooldownViewerCategorySet" in line: methods.add("C_CooldownViewer.GetCooldownViewerCategorySet")
    if "GetCooldownViewerCooldownInfo" in line: methods.add("C_CooldownViewer.GetCooldownViewerCooldownInfo")

print("Methods:", methods)
print("Fields:", fields)

with open("CDM_COMPATIBILITY_CONTRACT.md", "w") as out:
    out.write("# Minimum Compatibility Contract\n\n")
    out.write("## C_CooldownViewer API\n")
    out.write("- `C_CooldownViewer.GetCooldownViewerCategorySet(category, includeUnknown)`\n")
    out.write("- `C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)`\n\n")

    out.write("## Global Viewer Pools\n")
    out.write("- `EssentialCooldownViewer`\n")
    out.write("- `UtilityCooldownViewer`\n")
    out.write("- `BuffIconCooldownViewer`\n")
    out.write("- `BuffBarCooldownViewer`\n\n")
    out.write("Each viewer MUST have an `itemFramePool` with an `EnumerateActive()` iterator.\n\n")

    out.write("## Adapter Object (Frame mock)\n")
    out.write("Objects yielded by `EnumerateActive()` MUST have:\n")
    out.write("- Field: `cooldownID`\n")
    out.write("- Field: `cooldownInfo`\n")
    out.write("- Method: `GetSpellID(self)`\n")
    out.write("- Method: `GetAuraSpellID(self)` (based on EllesmereUI usage)\n")
