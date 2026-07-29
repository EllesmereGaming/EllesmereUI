import re
import sys

def fix_frame_lua():
    with open('Compatibility/Frame.lua', 'r') as f:
        content = f.read()
    
    # Remove the hallucinated EUI.API.ApplyUIObjectCompat
    content = re.sub(r'function EUI\.API\.ApplyUIObjectCompat\(frame\)\nend\n\n', '', content)
    
    with open('Compatibility/Frame.lua', 'w') as f:
        f.write(content)

def fix_setattr(filename):
    with open(filename, 'r') as f:
        content = f.read()
    
    # Replace obj:SetAttributeNoHandler(name, value) with EUI.API.SetSecureAttr(obj, name, value)
    content = re.sub(r'([a-zA-Z0-9_]+):SetAttributeNoHandler\(', r'EUI.API.SetSecureAttr(\1, ', content)
    
    with open(filename, 'w') as f:
        f.write(content)

fix_frame_lua()
fix_setattr('EllesmereUIActionBars/EllesmereUIActionBars.lua')
fix_setattr('EllesmereUIRaidFrames/EllesmereUIRaidFrames.lua')
print("Done")
