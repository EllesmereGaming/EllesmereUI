import re
import sys

def process_file(filename):
    with open(filename, 'r') as f:
        content = f.read()
    
    # Replace obj:SetAttributeNoHandler(name, value) with SetSecureAttr(obj, name, value)
    content = re.sub(r'([a-zA-Z0-9_]+):SetAttributeNoHandler\(', r'EUI_SetAttr(\1, ', content)
    
    helper = """local function EUI_SetAttr(frame, name, value)
    if not frame then return end
    if frame.SetAttributeNoHandler then
        frame:SetAttributeNoHandler(name, value)
    else
        frame:SetAttribute(name, EUI.API.FixSecureSnippet and type(value) == "string" and EUI.API.FixSecureSnippet(value) or value)
    end
end

"""
    if "local function EUI_SetAttr" not in content:
        # Insert right after the copyright / first lines
        content = helper + content
        
    with open(filename, 'w') as f:
        f.write(content)

process_file('EllesmereUIActionBars/EllesmereUIActionBars.lua')
process_file('EllesmereUIRaidFrames/EllesmereUIRaidFrames.lua')
print("Done")
